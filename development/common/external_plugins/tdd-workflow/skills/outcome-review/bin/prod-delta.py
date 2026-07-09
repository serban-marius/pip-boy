#!/usr/bin/env python3
"""outcome-review production-error delta.

Pure logic (Task 1): signature aggregation, baseline delta, changed-file ranking.
ES fetch + CLI modes are added in Task 2. `--selftest` runs offline (no cluster).
"""
import argparse
import atexit
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
import ssl
from datetime import datetime, timedelta, timezone

# --- signature helpers: COPY VERBATIM from alert-watcher fetch-alerts.py ---
_NORMALIZERS = [
    (re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I), "{UUID}"),
    (re.compile(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"), "{TS}"),
    (re.compile(r"(?<!\d)\d{10,13}(?!\d)"), "{TS}"),
    (re.compile(r"\d{1,3}(?:\.\d{1,3}){3}"), "{IP}"),
    (re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"), "{EMAIL}"),
    (re.compile(r"(SQL:\s*).+", re.S), r"\1{QUERY}"),
    (re.compile(r"tried to allocate \d+ bytes"), "tried to allocate {N} bytes"),
    (re.compile(r"Allowed memory size of \d+ bytes"), "Allowed memory size of {N} bytes"),
    (re.compile(r"after \d+ ms:"), "after {N} ms:"),
    (re.compile(r"Database:\s*\w+_\w+_db"), "Database: {DB}"),
    (re.compile(r"svc-[\w-]+\.[\w-]+"), "svc-{SERVICE}.{NAMESPACE}"),
    (re.compile(r"/\d{3,}/"), "/{ID}/"),
    (re.compile(r"line \d+"), "line {N}"),
    (re.compile(r":\d+\)"), ":{N})"),
    (re.compile(r"port \d+"), "port {N}"),
    (re.compile(r"PID \d+"), "PID {N}"),
    (re.compile(r"\b0x[0-9a-fA-F]+\b"), "{HEX}"),
    # Catch-all for remaining bare ints. Kept LAST so the targeted rules above can match
    # their richer context first (e.g. `line {N}` instead of just `{N}`).
    (re.compile(r"\b\d+\b"), "{N}"),
]


def _norm_msg(msg):
    """Normalize a log message for bucketing (strip volatile bits — UUIDs, timestamps, IPs,
    emails, numeric ids, PHP file:line tails, …) so the same underlying bug normalizes to the
    same string across runs. Patterns mirror error-watcher v2's `fingerprint-errors.py` so the
    two watchers can produce comparable signatures."""
    if not msg:
        return ""
    for pattern, replacement in _NORMALIZERS:
        msg = pattern.sub(replacement, msg)
    return " ".join(msg.split()).strip()


_EXCEPTION_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*(?:Exception|Error|Throwable))\b")
_VENDOR_PREFIXES = ("vendor/", "/vendor/", "node_modules/", "\\vendor\\")


# --- ES module constants and helpers (copied from error-watcher) ---

LOCAL_PORT = 19200
ES_HOST = f"https://localhost:{LOCAL_PORT}"
BATCH_SIZE = 500
MAX_DOCS = 10000
CURL_TIMEOUT = 30
PORT_FORWARD_PID = None


def die(msg):
    print(json.dumps({"error": msg}))
    sys.exit(1)


def cleanup():
    global PORT_FORWARD_PID
    if PORT_FORWARD_PID:
        try:
            os.killpg(os.getpgid(PORT_FORWARD_PID), signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass
        PORT_FORWARD_PID = None


atexit.register(cleanup)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
signal.signal(signal.SIGINT, lambda *_: sys.exit(1))


class ESError(Exception):
    pass


def es_request(path, body=None, creds=None):
    """Make an HTTPS request to ES, returning parsed JSON. Raises ESError on failure."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = f"{ES_HOST}/{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    if creds:
        import base64
        headers["Authorization"] = "Basic " + base64.b64encode(creds.encode()).decode()

    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=CURL_TIMEOUT, context=ctx) as resp:
            return json.loads(resp.read())
    except Exception as e:
        raise ESError(f"ES request failed ({path}): {e}") from e


def detect_context():
    """Find the production EUROPE kubectl context."""
    try:
        out = subprocess.check_output(
            ["kubectl", "config", "get-contexts", "-o", "name"],
            stderr=subprocess.DEVNULL, text=True, timeout=10
        )
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as e:
        die(f"Cannot list kubectl contexts: {e}")

    for name in out.strip().splitlines():
        if "EUROPE" in name.upper():
            return name.strip()
    die("No kubectl context containing 'EUROPE' found. Available: " + ", ".join(out.strip().splitlines()))


def start_port_forward(context):
    """Start kubectl port-forward in the background, return pid."""
    global PORT_FORWARD_PID
    proc = subprocess.Popen(
        [
            "kubectl", "port-forward",
            "-n", "logging-v2",
            "logging-product-europe-master-csi-0",
            f"{LOCAL_PORT}:9200",
            "--context", context,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )
    PORT_FORWARD_PID = proc.pid
    # Wait for tunnel to become ready
    for _ in range(15):
        time.sleep(1)
        try:
            es_request(
                f"kubertonic-logs-*-{datetime.now(timezone.utc).strftime('%Y.%m.%d')}/_search",
                body={"size": 1, "query": {"term": {"log_type": "php_message"}}},
                creds=sys.argv[1],
            )
            return
        except ESError:
            continue
    die("Port-forward tunnel did not become ready within 15s")


def index_pattern(days):
    """Return comma-separated index pattern covering the last N days."""
    now = datetime.now(timezone.utc)
    indices = []
    for i in range(days):
        d = now - timedelta(days=i)
        indices.append(f"kubertonic-logs-*-{d.strftime('%Y.%m.%d')}")
    return ",".join(indices)


SOURCE_FIELDS = [
    "message", "context", "kubernetes.labels.service",
    "kubernetes.labels.site", "kubernetes.namespace_name",
    "@timestamp", "level_name",
]


def build_query(services, gte, lte=None):
    """php_message ERROR/ALERT/CRITICAL for the given services, in [gte, lte] (lte optional)."""
    rng = {"gte": gte}
    if lte:
        rng["lte"] = lte
    return {
        "bool": {
            "must": [
                {"term": {"log_type": "php_message"}},
                {"exists": {"field": "level_name"}},
                {"terms": {"kubernetes.labels.service": services}},
                {"range": {"@timestamp": rng}},
            ],
            "should": [
                {"match_phrase": {"level_name": lv}} for lv in ("ALERT", "ERROR", "CRITICAL")
            ],
            "minimum_should_match": 1,
        }
    }


def get_total(creds, query, days):
    idx = index_pattern(days)
    body = {"size": 0, "track_total_hits": True, "query": query}
    try:
        resp = es_request(f"{idx}/_search", body=body, creds=creds)
    except ESError as e:
        die(str(e))
    return resp["hits"]["total"]["value"]


def fetch_docs(creds, total, query, days):
    """Paginate with search_after, fetch up to MAX_DOCS documents."""
    idx = index_pattern(days)
    docs = []
    search_after = None
    to_fetch = min(total, MAX_DOCS)

    while len(docs) < to_fetch:
        body = {
            "size": BATCH_SIZE,
            "query": query,
            "_source": SOURCE_FIELDS,
            "sort": [{"@timestamp": "desc"}],
        }
        if search_after:
            body["search_after"] = search_after

        try:
            resp = es_request(f"{idx}/_search", body=body, creds=creds)
        except ESError as e:
            die(str(e))
        hits = resp["hits"]["hits"]
        if not hits:
            break

        docs.extend(hits)
        search_after = hits[-1]["sort"]
        # Progress to stderr so it doesn't pollute JSON stdout
        print(f"  Fetched {len(docs)}/{to_fetch} documents...", file=sys.stderr)

    return docs


# --- Task-1 signature extraction and grouping ---

def _extract_exception_class(*sources):
    """First `*Exception` / `*Error` / `*Throwable` token found in any of the source strings.
    Empty string when none — that case still collides cleanly through the signature hash."""
    for source in sources:
        if not source:
            continue
        m = _EXCEPTION_RE.search(source)
        if m:
            return m.group(1)
    return ""


def _extract_top_frame(*sources):
    """First non-vendor PHP frame (`file.php:line` or `#0 /path/file.php(42)...`) across the
    given strings. Used as the third signature input — strengthens the hash when stack-traces
    are present, gracefully degrades to "" when they aren't."""
    for source in sources:
        if not isinstance(source, str) or not source:
            continue
        for line in source.splitlines():
            line = line.strip()
            if not line or any(p in line for p in _VENDOR_PREFIXES):
                continue
            m = re.search(r"(\S+\.php)(?:\((\d+)\))?", line)
            if m:
                return f"{m.group(1)}:{m.group(2)}" if m.group(2) else m.group(1)
    return ""


def compute_signature_hash(message, exception_class="", top_frame=""):
    """Stable 12-char SHA1 over (`normalized_message`, `exception_class`, `top_frame`) — same
    algorithm as error-watcher v2's `fingerprint-errors.py`. Empty strings stand in for
    missing inputs so two callers with different amounts of context still collide on the
    canonical message alone. Used as a deterministic dedup key in Jira summaries/descriptions
    (NOT as a label — labels are not free-text-searchable in JQL `text ~`)."""
    payload = "\x1f".join([_norm_msg(message), exception_class or "", top_frame or ""])
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:12]


def doc_signature(hit):
    """ES hit → signature dict. Pulls exception class/trace from context.exception when present."""
    src = hit.get("_source", {}) or {}
    msg = src.get("message", "") or ""
    ctx = src.get("context", {}) or {}
    exc = ctx.get("exception", {}) if isinstance(ctx, dict) else {}
    exc = exc if isinstance(exc, dict) else {}
    exc_class = exc.get("class", "") or _extract_exception_class(msg)
    trace = exc.get("trace") or exc.get("frames") or ""
    if isinstance(trace, list):
        trace = "\n".join(str(x) for x in trace)
    top_frame = _extract_top_frame(trace if isinstance(trace, str) else "", msg)
    return {
        "hash": compute_signature_hash(msg, exc_class, top_frame),
        "message": _norm_msg(msg),
        "exception_class": exc_class,
        "top_frame": top_frame,
    }


def aggregate_signatures(docs):
    """docs → {hash: {hash, message, exception_class, top_frame, count}} (first sample wins for text)."""
    out = {}
    for hit in docs:
        s = doc_signature(hit)
        e = out.setdefault(s["hash"], {**s, "count": 0})
        e["count"] += 1
    return out


def _frame_hits_changed(top_frame, changed):
    """True if the frame's file path plausibly refers to one of the changed files.
    Frame paths are absolute-in-container (e.g. /opt/app/laravel/app/Review/Foo.php);
    changed files are repo-relative (laravel/app/Review/Foo.php). Suffix match handles that.
    ponytail: basename match is the weak fallback — a collision across two same-named files is
    rare and only mislabels 'likely' vs 'coincidental', never drops or invents a finding."""
    if not top_frame:
        return False
    frame_file = top_frame.split(":", 1)[0]
    if not frame_file:
        return False
    base = frame_file.rsplit("/", 1)[-1]
    for cf in changed or []:
        if cf == frame_file or frame_file.endswith(cf) or cf.endswith(frame_file):
            return True
        if base and cf.rsplit("/", 1)[-1] == base:
            return True
    return False


def rank_new(baseline, after, changed_files):
    """Signatures in `after` absent from `baseline`, tagged likely_this_feature, likely-first."""
    new = []
    for h, sig in after.items():
        if h in baseline:
            continue
        item = dict(sig)
        item["likely_this_feature"] = _frame_hits_changed(sig.get("top_frame", ""), changed_files)
        new.append(item)
    new.sort(key=lambda s: (not s["likely_this_feature"], -s.get("count", 0)))
    return new


def _selftest():
    # 1. signature stability: volatile ids collapse to the same hash
    h1 = compute_signature_hash("User 123 not found", "ModelNotFoundException", "app/User.php:10")
    h2 = compute_signature_hash("User 456 not found", "ModelNotFoundException", "app/User.php:10")
    assert h1 == h2, "normalized message should collapse numeric ids"

    # 2. delta + ranking
    baseline = {"aaa": {"hash": "aaa", "message": "old", "exception_class": "", "top_frame": "", "count": 5}}
    after = {
        "aaa": {"hash": "aaa", "message": "old", "exception_class": "", "top_frame": "", "count": 9},
        "bbb": {"hash": "bbb", "message": "boom", "exception_class": "E",
                "top_frame": "/opt/app/laravel/app/Review/Foo.php:42", "count": 3},
        "ccc": {"hash": "ccc", "message": "unrelated", "exception_class": "E",
                "top_frame": "/opt/app/laravel/app/Other/Bar.php:1", "count": 7},
        "ddd": {"hash": "ddd", "message": "also boom", "exception_class": "E",
                "top_frame": "/opt/app/laravel/app/Review/Foo.php:99", "count": 1},
    }
    changed = ["laravel/app/Review/Foo.php"]
    new = rank_new(baseline, after, changed)
    hashes = [s["hash"] for s in new]
    assert "aaa" not in hashes, "baseline signature must never be reported"
    assert set(hashes) == {"bbb", "ccc", "ddd"}, hashes
    assert new[0]["hash"] == "bbb", "changed-file hit ranks first"
    assert new[0]["likely_this_feature"] is True
    assert new[1]["likely_this_feature"] is True, "ddd is also a likely (same changed-file) hit"
    # count-desc tie-break within the SAME (likely) bucket: bbb(count=3) must sort before ddd(count=1)
    likely = [s for s in new if s["likely_this_feature"]]
    assert [s["hash"] for s in likely] == ["bbb", "ddd"], "higher-count likely signature sorts first"
    assert new[2]["likely_this_feature"] is False
    print("prod-delta selftest OK")


def _fetch_signatures(creds, services, gte, lte, days):
    context = detect_context(); print(f"ctx {context}", file=sys.stderr)
    start_port_forward(context)
    q = build_query(services, gte, lte)
    total = get_total(creds, q, days)
    docs = fetch_docs(creds, total, q, days) if total else []
    print(f"fetched {len(docs)}/{total}", file=sys.stderr)
    return aggregate_signatures(docs)


def main():
    if "--selftest" in sys.argv:
        _selftest(); return
    ap = argparse.ArgumentParser()
    ap.add_argument("creds")                       # user:password
    ap.add_argument("--services", required=True)   # comma-separated
    ap.add_argument("--hours", type=int, default=24)
    ap.add_argument("--baseline", action="store_true")
    ap.add_argument("--since")                     # ISO; delta mode
    ap.add_argument("--baseline-file")             # delta mode: path to baseline signatures json
    ap.add_argument("--changed-file")              # delta mode: path to newline-separated changed files
    a = ap.parse_args()
    services = [s for s in a.services.split(",") if s]
    if a.baseline:
        sigs = _fetch_signatures(a.creds, services, f"now-{a.hours}h", None, a.hours // 24 + 2)
        print(json.dumps({"mode": "baseline", "services": services,
                          "window": f"{a.hours}h", "signatures": sigs}, indent=2))
        return
    if a.since:
        if a.baseline_file:
            try:
                baseline = json.load(open(a.baseline_file))["signatures"]
            except (OSError, ValueError, KeyError) as e:
                die(f"cannot read baseline file {a.baseline_file}: {e}")
        else:
            baseline = {}
        if a.changed_file:
            try:
                changed = [l.strip() for l in open(a.changed_file)]
            except OSError as e:
                die(f"cannot read changed-file {a.changed_file}: {e}")
        else:
            changed = []
        days = 3
        after = _fetch_signatures(a.creds, services, a.since, None, days)
        new = rank_new(baseline, after, changed)
        print(json.dumps({"mode": "delta", "window_from": a.since,
                          "new": new, "new_count": len(new),
                          "likely_count": sum(1 for s in new if s["likely_this_feature"])}, indent=2))
        return
    die("prod-delta: pass --baseline or --since")


if __name__ == "__main__":
    main()
