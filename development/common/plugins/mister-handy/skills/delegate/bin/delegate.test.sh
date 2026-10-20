#!/usr/bin/env bash
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
fails=0

expect() {
  if grep -qx -- "$3" <<<"$2"; then echo "ok   $1"
  else echo "FAIL $1: wanted '$3', got '$2'"; fails=$((fails + 1)); fi
}
mkdir -p "$tmp/stub"
cat >"$tmp/stub/gh" <<'EOF'
#!/bin/bash
case "$*" in
  "pr view"*) cat "$GH_STATE" ;;
  "pr list"*) cat "$GH_MERGED_HEADS" ;;
esac
EOF
cat >"$tmp/stub/orca" <<'EOF'
#!/bin/bash
cat "$ORCA_PS"
EOF
chmod +x "$tmp/stub/gh" "$tmp/stub/orca"
export PATH=$tmp/stub:$PATH GH_STATE=$tmp/state GH_MERGED_HEADS=$tmp/heads ORCA_PS=$tmp/ps.json
: >"$GH_MERGED_HEADS"
echo '{"result":{"worktrees":[]}}' >"$ORCA_PS"

HQ=$tmp/_hq
mkdir -p "$HQ" && echo '# append-only' >"$HQ/STATUS.md"
echo 1 >"$HQ/.watch-offset"
say() { echo "$1" >>"$HQ/STATUS.md"; }
watch() { perl -e 'alarm shift; exec @ARGV' "${2:-3}" bash "$here/watch.sh" "$HQ" "${1:-20}" 2>&1; }

say "10:00 hq DISPATCHED a"
say "10:01 a DONE-STEP PR description simplified"
expect "DONE-STEP wakes HQ"                     "$(watch)" "10:01 a DONE-STEP PR description simplified"
expect "after DONE-STEP the task is still live" "$(watch 0)" "QUIET 0m a "
say "10:02 a HANDOFF b tsnet ready, give b the go"
expect "HANDOFF wakes HQ"                       "$(watch)" "10:02 a HANDOFF b tsnet ready, give b the go"
say "10:02 a HANDOFF-FYI b touched terminal.create, keep it when you rebase"
expect "HANDOFF-FYI does not wake HQ"           "$(watch 20 2)" ""
say "10:03 a DONE no-code, report in _hq/reports/a.md"
watch >/dev/null
expect "a no-code DONE settles"                 "$(watch)" "ALL-SETTLED"

say "11:00 hq DISPATCHED c"
say "11:30 c DONE https://github.com/o/r/pull/7"
watch >/dev/null
echo OPEN >"$GH_STATE"
expect "an open PR keeps the watcher armed"     "$(watch 20 2)" ""
echo MERGED >"$GH_STATE"
expect "a merged PR wakes HQ"                   "$(watch)" "PR-MERGED c https://github.com/o/r/pull/7"
say "11:40 hq CLOSED c"
expect "closed after the merge settles"         "$(watch)" "ALL-SETTLED"
say "12:00 hq DISPATCHED d"
say "12:30 d DONE https://github.com/o/r/pull/8"
watch >/dev/null
echo CLOSED >"$GH_STATE"
expect "a PR closed unmerged wakes HQ"          "$(watch)" "PR-CLOSED d https://github.com/o/r/pull/8"
say "12:40 hq KEPT d follow-ups coming"
expect "kept settles too"                       "$(watch)" "ALL-SETTLED"

say "13:00 hq DISPATCHED e"
card() { echo "{\"result\":{\"worktrees\":[{\"path\":\"$tmp/$1\",\"status\":\"permission\",\"agents\":[{\"state\":\"blocked\",\"stateStartedAt\":$2,\"lastAssistantMessage\":\"Running the  e2e\\nsuite\"}]}]}}" >"$ORCA_PS"; }
card e $(( ($(date +%s) - 10) * 1000 ))
expect "a prompt under a minute old waits"      "$(watch 20 2)" ""
card e 1000
expect "a worker on a permission prompt wakes HQ" "$(watch)" "WAITING-APPROVAL e Running the e2e suite"
expect "the same prompt wakes HQ once"          "$(watch 20 2)" ""
card e 2000
expect "a new prompt wakes HQ again"            "$(watch)" "WAITING-APPROVAL e Running the e2e suite"
card other 1000
expect "only dispatched slugs count"            "$(watch 20 2)" ""
say "13:10 e DONE no-code"
watch >/dev/null

W=$tmp/wt
git init -q --bare "$tmp/remote.git"
git init -q -b main "$W" && git -C "$W" config user.email t@t && git -C "$W" config user.name t
git -C "$W" remote add origin "$tmp/remote.git"
git -C "$W" commit -q --allow-empty -m init && git -C "$W" push -q origin main
git -C "$W" checkout -qb feat/x
closable() { bash "$here/closable.sh" "$W" 2>&1; }
expect "clean and pushed is closable"           "$(closable)" "CLOSABLE"
echo x >"$W/new.txt"
expect "uncommitted work is kept"               "$(closable)" "KEEP uncommitted changes"
git -C "$W" add . && git -C "$W" commit -qm x
expect "a commit on no remote is kept"          "$(closable)" "KEEP commits on no remote branch and no merged PR with this head"
git -C "$W" rev-parse HEAD >"$GH_MERGED_HEADS"
expect "the head of a merged PR is closable"    "$(closable)" "CLOSABLE"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failing"; exit 1; }
