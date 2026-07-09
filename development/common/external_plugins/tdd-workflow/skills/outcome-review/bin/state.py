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

def _sanitize_key(key):
    """Keys become a path component under STATE_ROOT — sanitize so a branch-derived (or
    hand-passed) key can't nest directories or traverse out of STATE_ROOT."""
    k = (key or "").replace("/", "-")
    if not k or k in (".", "..") or ".." in k:
        die(f"invalid key: {key}")
    return k

def _dir(key): return STATE_ROOT / _sanitize_key(key)
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
    lock_path = _lock_file(key)
    if lock_path.exists():
        age = _hb_age(key)  # heartbeat: state.json last_iter_at (refreshed each tick)
        if age is None:
            # lock exists but no tick yet -> fall back to lock's own start time
            try:
                started_at = json.loads(lock_path.read_text()).get("started_at")
                age = _age(started_at)
            except (json.JSONDecodeError, OSError):
                age = None
        if age is not None and age < LOCK_FRESH_WINDOW_S:
            die(f"outcome-review already watching '{key}' (last activity {int(age)}s ago). "
                f"Use `/outcome-review --stop {key}` first.", code=2)
        # else: stale (no signal at all, or older than the window) -> take it over.
    lock_path.write_text(json.dumps({"pid": os.getppid(), "started_at": now_iso()}))
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

    # lock freshness must follow the heartbeat, not the lock's own started_at
    from datetime import timedelta
    key2 = "lock-freshness"
    old_iso = (datetime.now(timezone.utc) - timedelta(seconds=3600)).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Scenario A: fresh heartbeat, stale started_at -> must still be REFUSED
    assert _lock_acquire(key2)["acquired"] is True
    _init(key2, ["svc"], [], "main", None)  # writes recent last_iter_at
    lock_data = json.loads(_lock_file(key2).read_text())
    lock_data["started_at"] = old_iso
    _lock_file(key2).write_text(json.dumps(lock_data))
    try:
        _lock_acquire(key2); assert False, "expected refusal: fresh heartbeat must win over old started_at"
    except SystemExit as e:
        assert e.code == 2
    _lock_release(key2)

    # Scenario B: stale heartbeat and stale started_at -> must be TAKEN OVER
    assert _lock_acquire(key2)["acquired"] is True
    _init(key2, ["svc"], [], "main", None)
    st = _read(key2); st["last_iter_at"] = old_iso; _write(key2, st)
    lock_data = json.loads(_lock_file(key2).read_text())
    lock_data["started_at"] = old_iso
    _lock_file(key2).write_text(json.dumps(lock_data))
    assert _lock_acquire(key2)["acquired"] is True, "expected takeover of genuinely stale lock"

    # key sanitization: slashes collapse to a single dashed directory, traversal is rejected
    assert str(_dir("a/b")).endswith("a-b"), _dir("a/b")
    try:
        _dir("../x"); assert False, "expected rejection of a traversal key"
    except SystemExit:
        pass

    print("state selftest OK")

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
