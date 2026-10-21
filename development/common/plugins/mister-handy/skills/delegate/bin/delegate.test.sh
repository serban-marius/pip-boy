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

say "14:00 hq DISPATCHED f"
say "14:20 f ESCALATE 3 attempts failed (nan/glm5.3-flash nan/glm5.3-flash nan/deepseek-v4-flash)"
expect "ESCALATE wakes HQ"                      "$(watch)" "14:20 f ESCALATE 3 attempts failed (nan/glm5.3-flash nan/glm5.3-flash nan/deepseek-v4-flash)"
expect "an escalated task settles"              "$(watch)" "ALL-SETTLED"

cat >"$tmp/stub/curl" <<'EOF'
#!/bin/bash
cat >/dev/null
[ "${CURL_RC:-0}" -eq 0 ] || exit "$CURL_RC"
cat "$JEV_REPLY"; printf '\n%s' "${JEV_HTTP:-200}"
EOF
cat >"$tmp/stub/pi" <<'EOF'
#!/bin/bash
model=""; prev=""
for a in "$@"; do [ "$prev" = --model ] && model=$a; prev=$a; done
case " $* " in *" --tools "*) echo "reviewed $model" >>"$PI_CALLS"; cat "$PI_REVIEW"; exit 0 ;; esac
echo "$model" >>"$PI_CALLS"
printf '%s\n' "${@: -1}" >"$PI_LAST_PROMPT"
n=$(( $(cat "$PI_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$PI_COUNT"
case $(sed -n "${n}p" "$PI_PLAN") in
  pass) echo ok >done.txt ;;
  pass-new) echo ok >done.txt; echo new >new.txt; mkdir __pycache__; echo x >__pycache__/c.pyc ;;
  broken) echo ko >done.txt ;;
  atl) echo ok >done.txt; mkdir -p .atl; echo x >.atl/state; echo '.atl/' >>.gitignore ;;
  revised) echo ok >done.txt; echo renamed >notes.txt ;;
esac
EOF
chmod +x "$tmp/stub/curl" "$tmp/stub/pi"
export TYPESAFE_API_KEY=stub JEV_REPLY=$tmp/jev.json PI_PLAN=$tmp/plan PI_COUNT=$tmp/pi.count PI_CALLS=$tmp/pi.calls \
  PI_LAST_PROMPT=$tmp/pi.prompt PI_REVIEW=$tmp/review.txt MISTER_HANDY_JUDGE=/dev/null

B=$tmp/brief.md
brief() { printf '# t: write ok to done.txt\n%s\n\n## Task\nWrite ok to done.txt.\n%s\n\n## Reporting\nAppend lines to STATUS.md.\n' "$1" "$2" >"$B"; }
jev() { echo "{\"model\":\"jev-1.13.0\",\"answers\":{\"agent\":{\"type\":\"choice\",\"choice\":\"$1\",\"confidence\":$2,\"probabilities\":{\"$1\":0.83}}}}" >"$JEV_REPLY"; }
route() { bash "$here/route.sh" "$B" 2>&1; }
ACC='## Acceptance
grep -qx ok done.txt'
jev nan-flash 0.74
brief "Risk: low" ""
expect "no Acceptance routes to Claude"         "$(route)" "claude opus 1.00 no-acceptance"
brief "Risk: high" "$ACC"
expect "Risk: high routes to Claude"            "$(route)" "claude opus 1.00 risk-high"
brief "" "$ACC"
expect "no Risk line routes to Claude"          "$(route)" "claude opus 1.00 no-risk"
brief "Risk: low" "Then run the migration on production.
$ACC"
expect "a production write routes to Claude"    "$(route)" "claude opus 1.00 production"
brief "Risk: low" "Never touch prod.
$ACC"
expect "a confident nan-flash goes to pi"       "$(route)" "pi nan/glm5.3-flash 0.74 jev"
expect "the ladder head is the pi model"        "$(MISTER_HANDY_LADDER='nan/qwen3.6 1,nan/gemma4 1' route)" "pi nan/qwen3.6 0.74 jev"
jev nan-flash 0.41
expect "low confidence goes one tier up"        "$(route)" "claude sonnet 0.41 low-confidence:nan-flash"
jev claude-opus 0.9
expect "Jev picks Claude"                       "$(route)" "claude opus 0.90 jev"
expect "a Jev timeout routes to Claude"         "$(CURL_RC=28 route)" "claude opus 0.00 jev-timeout"
expect "a Jev error routes to Claude"           "$(JEV_HTTP=500 route)" "claude opus 0.00 jev-http-500"
echo '{"answers":{}}' >"$JEV_REPLY"
expect "an undecided Jev routes to Claude"      "$(route)" "claude opus 0.00 jev-undecided"

R=$tmp/repo
FHQ=$tmp/fhq
fresh() {
  rm -rf "$R" "$FHQ" "$PI_COUNT" "$PI_CALLS" && mkdir -p "$FHQ" && : >"$FHQ/STATUS.md"
  git init -q -b feat/t "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  [ -z "${1:-}" ] || printf '%s\n' "$1" >"$R/.gitignore"
  git -C "$R" add -A && git -C "$R" commit -q --allow-empty -m init
  printf '%s\n' "${@:2}" >"$PI_PLAN"
}
foreman() { (cd "$R" && bash "$here/foreman.sh" t "$B" "$FHQ" >/dev/null 2>&1; echo "exit $?"); }
states() { awk '{ printf "%s ", $3 }' "$FHQ/STATUS.md"; }
brief "Risk: low" "$ACC"

fresh "" pass
expect "a first-attempt pass exits 0"           "$(foreman)" "exit 0"
expect "a first-attempt pass is DONE"           "$(states)" "START MILESTONE DONE "
expect "DONE carries the commit sha"            "$(awk '$3 == "DONE" { print $4 }' "$FHQ/STATUS.md")" "$(git -C "$R" rev-parse --short HEAD)"
expect "the worker's change is committed"       "$(git -C "$R" log -1 --format=%s) $(git -C "$R" status --porcelain | wc -l | tr -d ' ')" "write ok to done.txt 0"
expect "the worker never sees Reporting"        "$(grep -c 'STATUS.md' "$PI_LAST_PROMPT")" "1"
expect "per-attempt logs are kept"              "$(ls "$FHQ/logs/t" | grep -c '^attempt-1\.')" "3"

fresh "" pass-new
brief "Risk: low" "$ACC
touch acceptance-artifact"
foreman >/dev/null
expect "build and acceptance artifacts are not committed" "$(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')" "done.txt new.txt "
brief "Risk: low" "$ACC"
fresh "" broken pass
foreman >/dev/null
expect "fail then pass is DONE"                 "$(states)" "START MILESTONE MILESTONE DONE "
expect "the retry gets the failure output"      "$(grep -c '^## Previous attempt failed' "$PI_LAST_PROMPT")" "1"
expect "a failed attempt is one MILESTONE"      "$(awk '$3 == "MILESTONE" { print $4, $5, $6, $7 }' "$FHQ/STATUS.md" | head -n 1)" "attempt 1/3 nan/glm5.3-flash FAIL"

fresh "" broken broken broken
expect "an exhausted ladder exits 3"            "$(foreman)" "exit 3"
expect "an exhausted ladder ESCALATEs"          "$(states)" "START MILESTONE MILESTONE MILESTONE ESCALATE "
expect "the ladder climbs"                      "$(tr '\n' ' ' <"$PI_CALLS")" "nan/glm5.3-flash nan/glm5.3-flash nan/deepseek-v4-flash "
expect "escalated work is left uncommitted"     "$(git -C "$R" log --oneline | wc -l | tr -d ' ')" "1"

fresh "" atl
foreman >/dev/null
expect "a stray .atl/ is removed"               "$(ls -A "$R" | grep -E '^\.(atl|gitignore)$')" ""
fresh "node_modules" atl
foreman >/dev/null
expect "a stray .gitignore line is removed"     "$(cat "$R/.gitignore") $(git -C "$R" show --stat --format= HEAD | grep -c gitignore)" "node_modules 0"

fresh "" pass
brief "Risk: low" ""
foreman >/dev/null
expect "no Acceptance is FAILED"                "$(states)" "FAILED "
brief "Risk: low" "$ACC"

fresh "" pass revised
printf 'Looks fine mostly.\nREVISE\n1. add notes.txt\n' >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 foreman >/dev/null
expect "REVISE gets one more worker round"      "$(tr '\n' ' ' <"$PI_CALLS")" "nan/glm5.3-flash reviewed nan/qwen3.6 nan/glm5.3-flash "
expect "the revised round is committed"         "$(git -C "$R" ls-files notes.txt) $(grep -c 'DONE.*review items applied' "$FHQ/STATUS.md")" "notes.txt 1"
fresh "" pass
echo PASS >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 foreman >/dev/null
expect "a review PASS is DONE"                  "$(awk '$3 == "DONE"' "$FHQ/STATUS.md" | grep -c 'review PASS')" "1"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failing"; exit 1; }
