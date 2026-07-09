# outcome-review Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `outcome-review` skill to the `tdd-workflow` plugin that reviews the outputs of a developed feature — did it work as intended (pre-merge), and did it introduce bugs (regressions pre-merge + new production errors post-deploy).

**Architecture:** A new skill inside the existing `tdd-workflow` plugin. Phase 1 (pre-merge, generic) reuses the plugin's own `workflows/adversarial-review.mjs` plus the project test runner. Phase 2 (post-deploy, softonic-ES-specific) is a self-paced `ScheduleWakeup` loop that diffs production error signatures against a pre-deploy baseline, ranks each new signature by whether its stack frame hits changed code, and triages confirmed regressions to Jira. Two new bundled Python scripts (`prod-delta.py`, `state.py`) do the telemetry and loop bookkeeping; everything else is skill prose + reuse.

**Tech Stack:** Markdown skill (`SKILL.md`), Python 3 stdlib only (no deps — matches sibling watchers), the existing `.mjs` Workflow, `gh` CLI, Atlassian MCP (Jira), kubectl + Elasticsearch (`$ES_CREDS`).

## Global Constraints

- **Python: stdlib only.** No `requests`/third-party imports — sibling scripts (`fetch-errors.py`, `state.py`) are stdlib-only; match them.
- **Progress to stderr, JSON to stdout.** Scripts print machine JSON on stdout and human progress on stderr, exactly like `fetch-errors.py`.
- **No Slack.** Explicit product decision — no Slack anywhere in this skill.
- **Softonic Jira constants** (reuse verbatim from the siblings): cloud ID `b8a5718d-fb17-46a5-a0d4-91b3c7896de0`, project `DS`, issuetype Bug (id `10732`), component field `customfield_11047`, parent = latest `BAU Maintenance Q{N}.{YY}` epic, labels include `data-watchers`.
- **ES creds:** the user's `$ES_CREDS` env var (`user:password`) is passed as the first script arg — never hardcode or prompt when it is set (per user global CLAUDE.md).
- **Signature hash algorithm is fixed and shared:** 12-char SHA1 over (`_norm_msg(message)`, `exception_class`, `top_frame`) joined by `\x1f`. Copy the four helpers verbatim from alert-watcher so regressions dedup against tickets the siblings created.
- **Version bump is mandatory:** any change under the plugin dir bumps `tdd-workflow` in BOTH `plugin.json` and `marketplace.json`, matching. New skill ⇒ minor (1.0.0 → 1.1.0).
- **Skill lives at:** `development/common/plugins/tdd-workflow/skills/outcome-review/`.

## Source files to copy from (exact paths in the local plugin cache)

- ES connection / port-forward / query / pagination:
  `~/.claude/plugins/cache/softonic-development-ai-plugins/error-watcher/1.1.0/skills/error-watcher/bin/fetch-errors.py`
- Signature helpers (`_norm_msg`, `_NORMALIZERS`, `_EXCEPTION_RE`, `_VENDOR_PREFIXES`, `_extract_exception_class`, `_extract_top_frame`, `compute_signature_hash`):
  `~/.claude/plugins/cache/softonic-development-ai-plugins/alert-watcher/1.2.0/skills/alert-watcher/bin/fetch-alerts.py` (lines ~745–864 for `_NORMALIZERS`+helpers)
- Lock / pacing / state structure:
  `~/.claude/plugins/cache/softonic-development-ai-plugins/alert-watcher/1.2.0/skills/alert-watcher/bin/state.py`
- Phase-1 review workflow (reused unchanged, in-plugin):
  `development/common/plugins/tdd-workflow/skills/tdd-workflow/workflows/adversarial-review.mjs` — args `{ baseBranch, ticketKey, criteria, diff }` → `{ verdict, confirmed, dismissed }`.

## File Structure

| File | Responsibility |
| --- | --- |
| `skills/outcome-review/SKILL.md` | Orchestrator: modes, Phase 1, Phase 2 loop, gates, Jira triage recipe |
| `skills/outcome-review/bin/prod-delta.py` | ES fetch scoped to services → aggregate signatures → baseline/delta → changed-file ranking. `--baseline`, `--since`, `--selftest` |
| `skills/outcome-review/bin/state.py` | Per-PR lock + minimal watch state + pacing + baseline path. `--key`-scoped commands + `--selftest` |
| `.claude-plugin/plugin.json` (modify) | version bump + description mention |
| `README.md` (modify) | document the new skill |
| `../../../../.claude-plugin/marketplace.json` (modify) | matching version bump + description |

---

## Task 1: `prod-delta.py` — signature aggregation, baseline delta, changed-file ranking (core logic, TDD)

This task builds ONLY the pure logic + its selftest. ES I/O is Task 2. Keeping the pure logic separate means the test cycle needs no cluster.

**Files:**
- Create: `skills/outcome-review/bin/prod-delta.py`

**Interfaces:**
- Produces (used by Task 2 and the selftest):
  - `compute_signature_hash(message, exception_class="", top_frame="") -> str` (copied verbatim)
  - `doc_signature(hit: dict) -> dict` → `{"hash", "message", "exception_class", "top_frame"}`
  - `aggregate_signatures(docs: list[dict]) -> dict[str, dict]` → `{hash: {hash, message, exception_class, top_frame, count}}`
  - `rank_new(baseline: dict, after: dict, changed_files: list[str]) -> list[dict]` → new signatures (not in baseline), each with added `"likely_this_feature": bool`, sorted likely-first then count-desc.

- [ ] **Step 1: Write the failing test (the selftest fn)**

Create `prod-delta.py` with ONLY this at first (imports + the selftest + a `__main__` that runs it when `--selftest` is passed):

```python
#!/usr/bin/env python3
"""outcome-review production-error delta.

Pure logic (Task 1): signature aggregation, baseline delta, changed-file ranking.
ES fetch + CLI modes are added in Task 2. `--selftest` runs offline (no cluster).
"""
import re
import sys

# --- signature helpers: COPY VERBATIM from alert-watcher fetch-alerts.py ---
# (_NORMALIZERS list, _norm_msg, _EXCEPTION_RE, _VENDOR_PREFIXES,
#  _extract_exception_class, _extract_top_frame, compute_signature_hash)
# Placeholder stubs here are REPLACED by the verbatim copies in Step 3.
def _norm_msg(msg): raise NotImplementedError
def _extract_exception_class(*s): raise NotImplementedError
def _extract_top_frame(*s): raise NotImplementedError
def compute_signature_hash(message, exception_class="", top_frame=""): raise NotImplementedError


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
    }
    changed = ["laravel/app/Review/Foo.php"]
    new = rank_new(baseline, after, changed)
    hashes = [s["hash"] for s in new]
    assert "aaa" not in hashes, "baseline signature must never be reported"
    assert set(hashes) == {"bbb", "ccc"}, hashes
    assert new[0]["hash"] == "bbb", "changed-file hit ranks first"
    assert new[0]["likely_this_feature"] is True
    assert new[1]["likely_this_feature"] is False
    print("prod-delta selftest OK")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
        sys.exit(0)
    print("prod-delta: no mode given (Task 2 adds --baseline/--since)", file=sys.stderr)
    sys.exit(2)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 skills/outcome-review/bin/prod-delta.py --selftest`
Expected: FAIL — `NotImplementedError` (helpers are stubs) or `NameError: rank_new` (not defined yet).

- [ ] **Step 3: Copy the signature helpers verbatim + implement the delta logic**

Replace the four stub functions with the **verbatim** copies from
`alert-watcher/1.2.0/skills/alert-watcher/bin/fetch-alerts.py` — the `_NORMALIZERS` list and `_norm_msg` (≈ lines 745–820), `_EXCEPTION_RE`, `_VENDOR_PREFIXES`, `_extract_exception_class`, `_extract_top_frame`, `compute_signature_hash` (lines 823–864). Then add the new logic:

```python
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
```

- [ ] **Step 4: Run the selftest to verify it passes**

Run: `python3 skills/outcome-review/bin/prod-delta.py --selftest`
Expected: PASS — prints `prod-delta selftest OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/outcome-review/bin/prod-delta.py
git commit -m "feat(outcome-review): signature delta + changed-file ranking (core logic)"
```

---

## Task 2: `prod-delta.py` — ES fetch scoped to services + `--baseline`/`--since` CLI

Adds the cluster I/O around the Task-1 logic. Not unit-tested (needs a live cluster); the test cycle is the Task-1 selftest still passing + an arg-parse smoke check.

**Files:**
- Modify: `skills/outcome-review/bin/prod-delta.py`

**Interfaces:**
- Consumes: Task-1 `aggregate_signatures`, `rank_new`.
- Produces (called by the SKILL):
  - `prod-delta.py <user:pass> --baseline --services a,b [--hours 24]` → stdout JSON `{"mode":"baseline","services":[...],"window":"24h","signatures":{hash:{...count}}}`
  - `prod-delta.py <user:pass> --since <ISO> --services a,b --baseline-file <path> --changed-file <path>` → stdout JSON `{"mode":"delta","new":[...ranked...],"new_count":N,"likely_count":M,"window_from":ISO}`

- [ ] **Step 1: Add the ES boilerplate (copy verbatim) + service-scoped query**

Copy verbatim from `error-watcher/1.1.0/.../fetch-errors.py`: the module constants (`LOCAL_PORT`, `ES_HOST`, `BATCH_SIZE`, `MAX_DOCS`, `CURL_TIMEOUT`, `PORT_FORWARD_PID`), `die`, `cleanup` + atexit/signal wiring, `ESError`, `es_request`, `detect_context`, `start_port_forward`, `index_pattern`, `get_total`, `fetch_docs`, and `SOURCE_FIELDS`. Add `context` to `SOURCE_FIELDS` if not present (it is). Then add a service-scoped query builder (the ONE new query piece):

```python
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
```

- [ ] **Step 2: Wire the two modes into `main()` / `__main__`**

Replace the Task-1 `__main__` block with argparse. `--selftest` still short-circuits offline (before any cluster call). Both cluster modes: detect context → port-forward → fetch → aggregate.

```python
import argparse, json, os
from datetime import datetime, timezone

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
        baseline = json.load(open(a.baseline_file))["signatures"] if a.baseline_file else {}
        changed = [l.strip() for l in open(a.changed_file)] if a.changed_file else []
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
```

- [ ] **Step 3: Verify the selftest still passes and argparse smoke-checks**

Run: `python3 skills/outcome-review/bin/prod-delta.py --selftest`
Expected: PASS `prod-delta selftest OK`.
Run: `python3 skills/outcome-review/bin/prod-delta.py --services x 2>&1 | head -1` (no cluster)
Expected: it reaches mode dispatch and errors with the `die` "pass --baseline or --since" JSON (proves argparse wired; a cluster call is NOT attempted without a mode). If it instead tries to port-forward, move the mode check before `_fetch_signatures`.

- [ ] **Step 4: Commit**

```bash
git add skills/outcome-review/bin/prod-delta.py
git commit -m "feat(outcome-review): ES fetch scoped to services with baseline/since modes"
```

---

## Task 3: `state.py` — per-PR lock, watch state, pacing (TDD)

Adapts alert-watcher's `state.py` to be keyed per feature (PR/branch slug) with a minimal watch state. Selftest runs offline.

**Files:**
- Create: `skills/outcome-review/bin/state.py`

**Interfaces:**
- Produces (called by the SKILL): commands, all requiring `--key <slug>`:
  - `lock-acquire` (exit 2 if a fresh lock exists), `lock-release`, `lock-check` (→ `{held, heartbeat_age_s}`)
  - `init --services a,b --changed-file <path> --base-branch <b> [--deploy-at ISO]` → writes state, echoes it
  - `tick` → bump pacing, return `{interval_s, iter_count, quiet_iters}` (arg `--active` resets to fast pacing)
  - `record-jira --hash <h> --jira <KEY>`
  - `show`, `reset --yes`
  - `baseline-path` → prints the absolute path where the baseline json for this key should live
- Pacing identical to alert-watcher: `PACING=[60,270,900]`, `BUMP_AT=[3,8]`, `LOCK_FRESH_WINDOW_S=1800`.

- [ ] **Step 1: Write the failing selftest**

Create `state.py` importing nothing project-specific, with a `_selftest()` exercising lock + pacing against a temp key, and `__main__` running it on `--selftest`:

```python
def _selftest():
    import tempfile, os
    global STATE_ROOT
    STATE_ROOT = Path(tempfile.mkdtemp())
    key = "selftest-key"
    assert _lock_check(key)["held"] is False
    assert _lock_acquire(key)["acquired"] is True
    # a fresh lock blocks a second acquire
    try:
        _lock_acquire(key); assert False, "expected fresh-lock refusal"
    except SystemExit as e:
        assert e.code == 2
    assert _lock_check(key)["held"] is True
    _lock_release(key)
    assert _lock_check(key)["held"] is False
    # pacing: quiet ticks widen the interval
    _init(key, ["svc"], [], "main", None)
    for _ in range(3):
        r = _tick(key, active=False)
    assert r["interval_s"] == 270, r
    for _ in range(5):
        r = _tick(key, active=False)
    assert r["interval_s"] == 900, r
    r = _tick(key, active=True)
    assert r["interval_s"] == 60, "activity resets pacing"
    print("state selftest OK")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 skills/outcome-review/bin/state.py --selftest`
Expected: FAIL — `NameError` (`_lock_check` etc. not defined).

- [ ] **Step 3: Implement, adapting alert-watcher's state.py**

Copy the helper scaffolding from `alert-watcher/1.2.0/.../state.py` verbatim where possible (`now_iso`, `_parse_iso`, `_age_seconds`, `write_state` tmp-replace pattern, `die`), but make paths key-scoped and state minimal. Full file:

```python
#!/usr/bin/env python3
"""Per-feature lock + watch state + pacing for the outcome-review post-deploy loop.
Keyed by a PR/branch slug so several features can be watched independently.
State dir: ~/.claude/state/outcome-review/<key>/ (state.json, baseline.json, .lock)."""
import argparse, json, os, shutil, sys
from datetime import datetime, timezone
from pathlib import Path

STATE_ROOT = Path.home() / ".claude" / "state" / "outcome-review"
PACING = [60, 270, 900]
BUMP_AT = [3, 8]
LOCK_FRESH_WINDOW_S = 1800

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def die(msg, code=1): print(json.dumps({"error": msg})); sys.exit(code)
def _dir(key): return STATE_ROOT / key
def _state_file(key): return _dir(key) / "state.json"
def _lock_file(key): return _dir(key) / ".lock"

def _parse_iso(iso):
    if not iso: return None
    try: return datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError: return None
def _age(iso):
    dt = _parse_iso(iso)
    return None if dt is None else (datetime.now(timezone.utc) - dt).total_seconds()

def _read(key):
    f = _state_file(key)
    return json.loads(f.read_text()) if f.exists() else None
def _write(key, st):
    _dir(key).mkdir(parents=True, exist_ok=True)
    tmp = _state_file(key).with_suffix(".tmp")
    tmp.write_text(json.dumps(st, indent=2, default=str)); tmp.replace(_state_file(key))

def _hb_age(key):
    st = _read(key)
    return _age(st.get("last_iter_at")) if st else None

def _lock_check(key):
    held = _lock_file(key).exists()
    out = {"held": held}
    if held: out["heartbeat_age_s"] = _hb_age(key)
    return out
def _lock_acquire(key):
    _dir(key).mkdir(parents=True, exist_ok=True)
    if _lock_file(key).exists():
        age = _hb_age(key)
        if age is not None and age < LOCK_FRESH_WINDOW_S:
            die(f"outcome-review already watching '{key}' (last tick {int(age)}s ago). "
                f"Use `/outcome-review --stop {key}` first.", code=2)
    _lock_file(key).write_text(json.dumps({"pid": os.getppid(), "started_at": now_iso()}))
    return {"acquired": True}
def _lock_release(key):
    if _lock_file(key).exists(): _lock_file(key).unlink()
    return {"released": True}

def _init(key, services, changed, base_branch, deploy_at):
    st = {"key": key, "services": services, "changed_files": changed,
          "base_branch": base_branch, "deploy_at": deploy_at or now_iso(),
          "started_at": now_iso(), "iter_count": 0, "quiet_iters": 0,
          "interval_s": PACING[0], "last_iter_at": now_iso(), "jiras": {}}
    _write(key, st); return st

def _tick(key, active):
    st = _read(key) or die(f"no state for '{key}'; run init first")
    st["iter_count"] += 1
    if active:
        st["quiet_iters"] = 0; st["interval_s"] = PACING[0]
    else:
        st["quiet_iters"] += 1; q = st["quiet_iters"]
        st["interval_s"] = PACING[2] if q >= BUMP_AT[1] else PACING[1] if q >= BUMP_AT[0] else PACING[0]
    st["last_iter_at"] = now_iso(); _write(key, st)
    return {"interval_s": st["interval_s"], "iter_count": st["iter_count"], "quiet_iters": st["quiet_iters"]}

def _record_jira(key, h, jira):
    st = _read(key) or die(f"no state for '{key}'")
    st.setdefault("jiras", {})[h] = jira; _write(key, st); return {"ok": True}

def _reset(key):
    d = _dir(key)
    if d.exists(): shutil.rmtree(d)
    return {"reset": True, "key": key}

def _selftest():
    # (as written in Step 1)
    ...

def main():
    if "--selftest" in sys.argv:
        _selftest(); return
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("lock-acquire", "lock-release", "lock-check", "show", "baseline-path"):
        sub.add_parser(name).add_argument("--key", required=True)
    pi = sub.add_parser("init"); pi.add_argument("--key", required=True)
    pi.add_argument("--services", required=True); pi.add_argument("--changed-file", required=True)
    pi.add_argument("--base-branch", required=True); pi.add_argument("--deploy-at")
    pt = sub.add_parser("tick"); pt.add_argument("--key", required=True); pt.add_argument("--active", action="store_true")
    pj = sub.add_parser("record-jira"); pj.add_argument("--key", required=True)
    pj.add_argument("--hash", required=True); pj.add_argument("--jira", required=True)
    prr = sub.add_parser("reset"); prr.add_argument("--key", required=True); prr.add_argument("--yes", action="store_true")
    a = ap.parse_args()
    k = a.key
    if a.cmd == "lock-acquire": print(json.dumps(_lock_acquire(k)))
    elif a.cmd == "lock-release": print(json.dumps(_lock_release(k)))
    elif a.cmd == "lock-check": print(json.dumps(_lock_check(k)))
    elif a.cmd == "show": print(json.dumps(_read(k), indent=2, default=str))
    elif a.cmd == "baseline-path": print(str(_dir(k) / "baseline.json"))
    elif a.cmd == "init":
        changed = [l.strip() for l in open(a.changed_file) if l.strip()]
        print(json.dumps(_init(k, [s for s in a.services.split(",") if s], changed, a.base_branch, a.deploy_at), indent=2))
    elif a.cmd == "tick": print(json.dumps(_tick(k, a.active)))
    elif a.cmd == "record-jira": print(json.dumps(_record_jira(k, a.hash, a.jira)))
    elif a.cmd == "reset":
        if not a.yes: die("reset requires --yes", code=2)
        print(json.dumps(_reset(k)))

if __name__ == "__main__":
    main()
```

Paste the Step-1 `_selftest()` body in place of the `...`.

- [ ] **Step 4: Run the selftest to verify it passes**

Run: `python3 skills/outcome-review/bin/state.py --selftest`
Expected: PASS — prints `state selftest OK`.

- [ ] **Step 5: Commit**

```bash
git add skills/outcome-review/bin/state.py
git commit -m "feat(outcome-review): per-feature lock + watch pacing state"
```

---

## Task 4: `SKILL.md` — the orchestrator

**Files:**
- Create: `skills/outcome-review/SKILL.md`

This is prose (no unit test). The deliverable is a complete SKILL.md with the sections and content below. Where it says "reuse the recipe from X", the implementer copies the concrete steps from that sibling SKILL (already read during planning). `BIN` = `${CLAUDE_PLUGIN_ROOT}/skills/outcome-review/bin`.

- [ ] **Step 1: Write the frontmatter + intro (verbatim)**

```markdown
---
name: outcome-review
description: >
  Review the OUTPUTS of a developed feature (a PR/branch): did it work as intended, and did it
  introduce bugs. Phase 1 (pre-merge) runs the project tests + an adversarial review of the diff
  against the feature's acceptance criteria and posts a PR-comment verdict. Phase 2 (post-deploy)
  is a self-paced loop that diffs production error signatures against a pre-deploy baseline for the
  feature's services, ranks each new signature by whether its stack frame hits changed code, and
  triages confirmed regressions to Jira (no Slack). Use when the user says "outcome-review",
  "review the outputs", "did my feature work", "check for regressions", "watch this PR after deploy",
  or "/outcome-review <pr|branch>". Natural continuation of tdd-workflow after it ships a PR.
---
```

Then an intro paragraph: what it does, the two phases, and that Phase 2 is softonic-ES-specific while Phase 1 is generic. State `BIN` resolution (as alert-watcher does).

- [ ] **Step 2: Write the Modes section**

Document the four modes exactly as in the design doc (`<pr|branch>`, `--watch <pr>`, `--status <pr>`, `--stop <pr>`). Include the rule: derive a stable `<key>` slug from the branch name (e.g. `feat/DS-3671-foo` → `DS-3671-foo`); every state/lock/baseline op passes `--key <key>`.

- [ ] **Step 3: Write Phase 1 (pre-merge review)**

Steps, matching the design doc §"Phase 1":
1. **Resolve base + diff.** `BASE=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@.*/@@')` fallback to fork point; `git --no-pager diff $BASE` captured ONCE into a variable for the review.
2. **Resolve acceptance criteria** in priority order: spec-kit `specs/NNN/spec.md` (grep the branch/ticket slug against `specs/README.md`) → PR body (`gh pr view --json body`) → linked Jira (parse `DS-\d+` from branch, `jira_get_issue`). Show what was found; confirm if ambiguous.
3. **Resolve the feature's services** (needed for Phase 2, captured now): derive candidates from the repo (helm `values*.yaml` service label, namespace, or repo name) and confirm/override once with `AskUserQuestion`. Save with `state.py init` later.
4. **Run tests** — detect the runner (this ecosystem: `./laravel/core/bin/remotePHP vendor/bin/phpunit` or the `rg-test` docker image; see review-generator memory). **Smoke-test it is alive first** (a trivial run); if the cluster/DB is down, STOP and ask the user to bring it up. Then run the full suite + the feature's own tests. Failures = candidate regressions.
5. **Adversarial review**: invoke the in-plugin workflow via the Workflow tool:
   `Workflow({ scriptPath: "${CLAUDE_PLUGIN_ROOT}/skills/tdd-workflow/workflows/adversarial-review.mjs", args: { baseBranch: BASE, ticketKey, criteria, diff } })`. Read `{verdict, confirmed, dismissed}`.
6. **🚦 GATE**: present verdict + test results + confirmed findings. Ask before posting the PR comment. On OK, `gh pr comment <pr> --body "<summary>"`.
7. **Capture pre-deploy baseline**: `state.py init --key ... --services ... --changed-file <(git diff --name-only $BASE) --base-branch $BASE`, then `python3 $BIN/prod-delta.py "$ES_CREDS" --baseline --services <svcs> > $(python3 $BIN/state.py baseline-path --key <key>)`. Tell the user Phase 2 is armed: run `/outcome-review --watch <key>` AFTER deploying.

- [ ] **Step 4: Write Phase 2 (post-deploy watch loop)**

Mirror alert-watcher's A-section loop, adapted:
- **Boot**: `state.py lock-check --key`; if not held or stale → `lock-acquire` (exit 2 → another live watcher, STOP). Record deploy time = now (or `--deploy-at`). If no baseline file exists, warn it is not a true pre-deploy baseline and baseline now.
- **Tick**: `prod-delta.py "$ES_CREDS" --since <deploy_at> --services <svcs> --baseline-file <path> --changed-file <path>` → read `new` (ranked). `state.py tick --key [--active]` (active iff any `likely_this_feature`).
- **Triage** (for each `likely_this_feature` signature, up to ~3 parallel): dedup against open DS Jiras by `text ~ "#<hash>"` (reuse alert-watcher P2c step 1); if none, dig root cause and create a Bug (reuse the alert-watcher/error-watcher **create** recipe verbatim: BAU epic, `customfield_11047` component from the service, `#<hash>` in summary, `data-watchers` label, description with root cause + sample request-ids + next steps). **First creation in a session gets a go-ahead prompt.** `state.py record-jira --key --hash --jira`.
- **Schedule**: `ScheduleWakeup delaySeconds:<interval_s> prompt:"/outcome-review --watch <key>" reason:"outcome-review post-deploy tick"`. Auto-close after the window (default 4h since `started_at`, or all-quiet past the widest pacing): post the final PR comment (clean, or N regressions + Jira links), `lock-release`, and stop.
- Emit one quiet status line per tick, like alert-watcher.

- [ ] **Step 5: Write Modes C (`--status`/`--stop`) + Error handling + Files sections**

- `--status <key>`: `state.py show --key` → render compactly; exit.
- `--stop <key>`: `state.py reset --key --yes` → "watch stopped, state cleared"; a loop scheduled elsewhere exits on its next tick (lock-check → not held); exit.
- **Error handling** (copy the design doc's list): test env down → stop+ask; ES key/cluster unreachable → post findings without the delta, don't block; single Jira failure → log+continue; no criteria → warn+review diff alone; fresh lock held → stop.
- **Files** section listing `bin/prod-delta.py`, `bin/state.py`, and the reused `../tdd-workflow/workflows/adversarial-review.mjs`.

- [ ] **Step 6: Sanity-check the skill loads**

Run: `python3 -c "import pathlib,re,sys; t=pathlib.Path('skills/outcome-review/SKILL.md').read_text(); assert t.startswith('---'); fm=t.split('---',2)[1]; assert 'name: outcome-review' in fm and 'description:' in fm; print('SKILL.md frontmatter OK')"`
Expected: `SKILL.md frontmatter OK`.

- [ ] **Step 7: Commit**

```bash
git add skills/outcome-review/SKILL.md
git commit -m "feat(outcome-review): orchestrator skill (phase 1 review + phase 2 watch)"
```

---

## Task 5: Packaging — version bump + registration + docs

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `README.md`
- Modify: `../../../../.claude-plugin/marketplace.json` (marketplace root)

- [ ] **Step 1: Bump `plugin.json` and mention the new skill**

In `development/common/plugins/tdd-workflow/.claude-plugin/plugin.json`:

```json
  "version": "1.1.0",
  "description": "Take a ticket from JIRA to a PR with a team of specialized agents in TDD, with two human gates, then review the shipped outputs (outcome-review: pre-merge verdict + post-deploy regression watch). Stack-agnostic.",
```
(only the `version` and `description` fields change.)

- [ ] **Step 2: Bump the matching marketplace entry**

In the repo-root `.claude-plugin/marketplace.json`, find the `tdd-workflow` object and set `"version": "1.1.0"` and the same `description` as Step 1. Add `"outcome-review"` to its `keywords` array.

- [ ] **Step 3: Document the skill in README.md**

Add a section to `development/common/plugins/tdd-workflow/README.md` describing `outcome-review`: purpose, the two phases, the four modes, and that Phase 2 assumes the softonic prod stack (ES via `$ES_CREDS`, Jira `DS`). Keep it to ~15 lines.

- [ ] **Step 4: Verify both versions match**

Run: `python3 -c "import json; a=json.load(open('.claude-plugin/plugin.json'))['version']; import glob; m=[p for p in json.load(open('/Users/mariusserban/.claude/plugins/marketplaces/softonic-development-ai-plugins/.claude-plugin/marketplace.json'))['plugins'] if p['name']=='tdd-workflow'][0]['version']; assert a==m=='1.1.0', (a,m); print('versions match', a)"`
(run from the plugin dir)
Expected: `versions match 1.1.0`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json README.md ../../../../.claude-plugin/marketplace.json
git commit -m "chore(tdd-workflow): register outcome-review skill, bump to 1.1.0"
```

---

## Task 6: End-to-end validation (manual checklist)

Phase 2 needs a live deploy, so full automation isn't possible. Validate what can be:

- [ ] **Selftests green:** `python3 skills/outcome-review/bin/prod-delta.py --selftest` and `python3 skills/outcome-review/bin/state.py --selftest` both print `... OK`.
- [ ] **Phase 1 dry run** against a real branch that has a spec + PR (e.g. review-generator `feat/DS-3671-review-validator-agent`): confirm the skill resolves the base branch, finds `specs/004-review-validator-agent/spec.md`, resolves `DS-3671`, and hands a criteria+diff to `adversarial-review.mjs` (let it run; confirm a verdict comes back). Confirm the PR-comment step is GATED (asks first).
- [ ] **prod-delta baseline smoke** (cluster up): `python3 $BIN/prod-delta.py "$ES_CREDS" --baseline --services review-generator --hours 1` returns JSON with a `signatures` map (may be empty). If auth fails, confirm the skill degrades (reports without the delta) instead of crashing.
- [ ] **Loop lock**: run `--watch <key>` twice quickly; the second must refuse with the exit-2 "already watching" message.
- [ ] **Document** in the PR description that Phase 2's live regression path was validated only at the baseline/lock level; the deploy-triggered delta+Jira path is exercised on the first real feature.

---

## Self-Review (completed during planning)

- **Spec coverage:** Phase 1 (Task 4 §Phase1 + reuse) ✓; Phase 2 loop (Task 4 §Phase2) ✓; layered correlation = `rank_new` + `_frame_hits_changed` (Task 1) ✓; baseline delta (Tasks 1–2) ✓; Jira triage no-Slack (Task 4 step 4) ✓; modes (Task 4 steps 2,5) ✓; service resolution (Task 4 step 3) ✓; packaging/version bump (Task 5) ✓; selftests (Tasks 1,3) ✓.
- **Placeholder scan:** the only "copy verbatim from <path>" references point at concrete, named functions in specific files read during planning — not vague TODOs. The `...` in Task 3 Step 3 is explicitly filled from Step 1.
- **Type consistency:** `aggregate_signatures`/`rank_new`/`doc_signature` signatures match between Task 1 (definition) and Task 2 (caller); `state.py` command/flag names match between Task 3 (definition) and Task 4 (caller): `init/tick/record-jira/lock-*/baseline-path/reset`, all `--key`-scoped.
