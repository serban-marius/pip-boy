#!/usr/bin/env bash
set -u
while IFS= read -r v; do
  case $v in
    MISTER_HANDY_* | GIT_CONFIG_COUNT | GIT_CONFIG_KEY_* | GIT_CONFIG_VALUE_* | GIT_TERMINAL_PROMPT) unset "$v" ;;
  esac
done < <(compgen -e)
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
  "pr create"*) cat "$GH_PR_URL" ;;
esac
EOF
cat >"$tmp/stub/orca" <<'EOF'
#!/bin/bash
cat "$ORCA_PS"
EOF
cat >"$tmp/stub/claude" <<'EOF'
#!/bin/bash
model=""; prev=""
for a in "$@"; do [ "$prev" = --model ] && model=$a; prev=$a; done
echo "claude $model" >>"$PI_CALLS"
printf '%s\n' "$@" >>"$CLAUDE_ARGS"
case " $* " in *" Read,Grep,Glob "*) cat >/dev/null; jq -n --rawfile r "$PI_REVIEW" '{type: "result", is_error: false, result: $r}'; exit 0 ;; esac
cat >"$PI_LAST_PROMPT"
n=$(( $(cat "$PI_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$PI_COUNT"
case $(sed -n "${n}p" "$PI_PLAN") in
  pass) echo ok >done.txt ;;
  broken) echo ko >done.txt ;;
  capped) echo ko >done.txt; echo '{"type":"result","subtype":"error_max_turns","is_error":true}'; exit 1 ;;
  ratelimited) echo '{"type":"result","subtype":"success","is_error":true,"result":"API Error: 429 rate_limit_error"}'; exit 1 ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"result":"done"}'
EOF
printf '#!/bin/sh\nexit 44\n' >"$tmp/stub/security"
chmod +x "$tmp/stub/gh" "$tmp/stub/orca" "$tmp/stub/claude" "$tmp/stub/security"
export PATH=$tmp/stub:$PATH GH_PR_URL=$tmp/pr-url GH_STATE=$tmp/state GH_MERGED_HEADS=$tmp/heads ORCA_PS=$tmp/ps.json \
  XDG_CONFIG_HOME=$tmp/xdg CLAUDE_ARGS=$tmp/claude.args MISTER_HANDY_LADDER="pi:nan/deepseek-v4-flash 2,pi:nan/glm5.3-flash 1"
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
mkdir -p "$tmp/notgit"
expect "a missing worktree is already gone"    "$(bash "$here/closable.sh" "$tmp/missing" 2>&1)" "GONE $tmp/missing"
expect "an existing non-git dir is kept"        "$(bash "$here/closable.sh" "$tmp/notgit" 2>&1)" "KEEP not a git worktree: $tmp/notgit"

say "14:00 hq DISPATCHED f"
say "14:20 f ESCALATE 3 attempts failed (nan/deepseek-v4-flash nan/deepseek-v4-flash nan/glm5.3-flash)"
expect "ESCALATE wakes HQ"                      "$(watch)" "14:20 f ESCALATE 3 attempts failed (nan/deepseek-v4-flash nan/deepseek-v4-flash nan/glm5.3-flash)"
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
sd=""
for a in "$@"; do [ "$prev" = --model ] && model=$a; [ "$prev" = --session-dir ] && sd=$a; prev=$a; done
case " $* " in *" --tools "*) echo "reviewed $model" >>"$PI_CALLS"; cat "$PI_REVIEW"; exit 0 ;; esac
echo "$model" >>"$PI_CALLS"
case " $* " in *" -ne "*) ;; *) echo "extensions on" >>"$PI_CALLS" ;; esac
printf '%s\n' "${@: -1}" >"$PI_LAST_PROMPT"
printf '%s\n' "${@:1:$#-1}" >>"$PI_ARGS"
[ -z "${PI_ADVISOR_LINES:-}" ] || cat "$PI_ADVISOR_LINES" >>"$MISTER_HANDY_ADVISOR_LOG"
n=$(( $(cat "$PI_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$PI_COUNT"
case $(sed -n "${n}p" "$PI_PLAN") in
  pass) echo ok >done.txt ;;
  ratelimited) echo "Error: 429 Too Many Requests: max_parallel_requests exceeded" >&2; exit 1 ;;
  config) echo ok >done.txt; printf 'token = os.environ.get("TOKEN")\napi_key = settings.OPENAI_KEY\n' >conf.py ;;
  edits-test) echo ok >done.txt; echo x >ok.txt ;;
  pass-new) echo ok >done.txt; echo new >new.txt; mkdir __pycache__; echo x >__pycache__/c.pyc ;;
  broken) echo ko >done.txt ;;
  capped) echo ko >done.txt; mkdir -p "$sd"; printf '{"type":"message","message":{"role":"assistant","stopReason":"length"}}\n' >"$sd/$(printf %04d "$n").jsonl" ;;
  atl) echo ok >done.txt; mkdir -p .atl; echo x >.atl/state; printf '# Local Pi runtime state\n.atl/\n' >>.gitignore ;;
  atl-and-edit) echo ok >done.txt; mkdir -p .atl; printf 'logs/\n# Local Pi runtime state\n.atl/\n' >>.gitignore ;;
  revised) echo ok >done.txt; echo renamed >notes.txt ;;
  outside) echo ok >done.txt; echo x >other.txt; mkdir -p src/sub; echo y >src/sub/y.py ;;
  revert) rm -f other.txt ;;
  secret) echo ok >done.txt; echo 'API_KEY = "abcd1234efgh5678ijkl"' >config.py ;;
  dotenv) echo ok >done.txt; echo X=1 >.env.local ;;
  hang) sleep 30 & echo $! >"$PI_CHILD"; sleep 30 ;;
  slow) sleep 3; echo ok >done.txt ;;
  pushy) echo ok >done.txt; git push -q origin HEAD 2>/dev/null; gh pr create 2>/dev/null && touch gh-ran ;;
  branchy) git checkout -qb elsewhere; echo ok >done.txt ;;
  breaks) echo ko >done.txt; echo junk >junk.txt; mkdir -p newdir/sub; echo j >newdir/sub/j.txt ;;
esac
EOF
chmod +x "$tmp/stub/curl" "$tmp/stub/pi"
export TYPESAFE_API_KEY=stub JEV_REPLY=$tmp/jev.json PI_PLAN=$tmp/plan PI_ARGS=$tmp/pi.args PI_COUNT=$tmp/pi.count PI_CALLS=$tmp/pi.calls \
  PI_LAST_PROMPT=$tmp/pi.prompt PI_REVIEW=$tmp/review.txt MISTER_HANDY_JUDGE=/dev/null PI_CHILD=$tmp/pi.child \
  MISTER_HANDY_SLOT_DIR=$tmp/slots MISTER_HANDY_SLOT_POLL=1 MISTER_HANDY_RATE_BACKOFF=0

B=$tmp/brief.md
brief() { printf '# t: write ok to done.txt\n%s\n\n## Task\nWrite ok to done.txt.\n%s\n\n## Reporting\nAppend lines to STATUS.md.\n' "$1" "$2" >"$B"; }
jev() { echo "{\"model\":\"jev-1.13.0\",\"answers\":{\"agent\":{\"type\":\"choice\",\"choice\":\"$1\",\"confidence\":$2,\"probabilities\":{\"$1\":0.83}}}}" >"$JEV_REPLY"; }
route() { bash "$here/route.sh" "$B" 2>&1; }
ACC='## Acceptance
grep -qx ok done.txt'
jev cheap 0.74
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
expect "a confident nan-flash goes to pi"       "$(route)" "foreman pi:nan/deepseek-v4-flash 0.74 jev"
expect "the ladder head is the pi model"        "$(MISTER_HANDY_LADDER='nan/qwen3.6 1,nan/gemma4 1' route)" "foreman pi:nan/qwen3.6 0.74 jev"
jev cheap 0.41
expect "low confidence goes one tier up"        "$(route)" "claude sonnet 0.41 low-confidence:cheap"
jev top 0.9
expect "Jev picks Claude"                       "$(route)" "claude opus 0.90 jev"
expect "a Jev timeout routes to Claude"         "$(CURL_RC=28 route)" "claude sonnet 0.00 jev-timeout"
expect "a Jev error routes to Claude"           "$(JEV_HTTP=500 route)" "claude sonnet 0.00 jev-http-500"
jev cheap 0.74
expect "an empty ladder routes to Claude"        "$(MISTER_HANDY_LADDER=' ' route)" "claude sonnet 0.74 empty-ladder"
brief "Risk: low" "## Acceptance
\`test -f x\` passes"
expect "a prose Acceptance line routes to Claude" "$(route)" "claude opus 1.00 acceptance-not-runnable"
brief "Risk: low" "Never touch prod.
$ACC"
brief "Risk: low" "Make the production edit in src/x.ts; keep production code paths.
$ACC"
expect "editing production source is ordinary work" "$(route)" "foreman pi:nan/deepseek-v4-flash 0.74 jev"
brief "Risk: low
Prod: yes" "$ACC"
expect "Prod: yes routes to Claude"             "$(route)" "claude opus 1.00 production"
brief "Risk: low
Prod: no" "Then deploy to prod after merge.
$ACC"
expect "Prod: no overrides the keywords"        "$(route)" "foreman pi:nan/deepseek-v4-flash 0.74 jev"
brief "Risk: low" "Never touch prod.
$ACC"
echo '{"answers":{}}' >"$JEV_REPLY"
expect "an undecided Jev routes to Claude"      "$(route)" "claude sonnet 0.00 jev-undecided"
brief "Risk: normal" "$ACC"
expect "rules router sends a Risk normal brief with Acceptance to the foreman" "$(MISTER_HANDY_ROUTER=rules route)" "foreman pi:nan/deepseek-v4-flash 1.00 rules"
expect "rules router is used when no Jev key exists" "$(env -u TYPESAFE_API_KEY bash "$here/route.sh" "$B" 2>&1)" "foreman pi:nan/deepseek-v4-flash 1.00 rules"
expect "the jev router without a key is mid"    "$(MISTER_HANDY_ROUTER=jev env -u TYPESAFE_API_KEY bash "$here/route.sh" "$B" 2>&1)" "claude sonnet 0.00 jev-no-key"
brief "Risk: high" "$ACC"
expect "rules router keeps the hard gates"      "$(MISTER_HANDY_ROUTER=rules MISTER_HANDY_TOP='claude fable' route)" "claude fable 1.00 risk-high"
expect "the plugin default ladder is claude-only" "$(unset MISTER_HANDY_LADDER; . "$here/brief.sh"; ladder | tr '\n' ' ')" "claude:haiku 2 claude:sonnet 1 "
mkdir -p "$XDG_CONFIG_HOME/mister-handy" && printf '# mine\npi:openrouter/qwen/qwen3-coder 2\nollama/qwen3:8b\n' >"$XDG_CONFIG_HOME/mister-handy/ladder"
expect "the ladder comes from ~/.config when set" "$(unset MISTER_HANDY_LADDER; . "$here/brief.sh"; ladder | tr '\n' ' ')" "pi:openrouter/qwen/qwen3-coder 2 pi:ollama/qwen3:8b 1 "
expect "MISTER_HANDY_LADDER beats ~/.config"    "$(. "$here/brief.sh"; ladder | head -n 1)" "pi:nan/deepseek-v4-flash 2"
rm -r "$XDG_CONFIG_HOME/mister-handy"

R=$tmp/repo
FHQ=$tmp/fhq
fresh() {
  rm -rf "$R" "$FHQ" "$PI_COUNT" "$PI_CALLS" "$PI_ARGS" "$CLAUDE_ARGS" "$tmp/origin.git" && mkdir -p "$FHQ" && : >"$FHQ/STATUS.md"
  git init -q -b feat/t "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  [ -z "${1:-}" ] || printf '%s\n' "$1" >"$R/.gitignore"
  git -C "$R" add -A && git -C "$R" commit -q --allow-empty -m init
  git init -q --bare "$tmp/origin.git" && git -C "$R" remote add origin "$tmp/origin.git"
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

fresh "" pass
brief "Risk: low" '## Acceptance
test -z "${MISTER_HANDY_FOO:-}${GIT_CONFIG_COUNT:-}"'
expect "acceptance runs without MISTER_HANDY_ or GIT_CONFIG_ vars" "$(export MISTER_HANDY_FOO=x GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=mister.handy.test GIT_CONFIG_VALUE_0=1; foreman; states)" "exit 0
START MILESTONE DONE "

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
expect "a failed attempt is one MILESTONE"      "$(awk '$3 == "MILESTONE" { print $4, $5, $6, $7 }' "$FHQ/STATUS.md" | head -n 1)" "attempt 1/3 pi:nan/deepseek-v4-flash FAIL"

fresh "" broken broken broken
expect "an exhausted ladder exits 3"            "$(foreman)" "exit 3"
expect "an exhausted ladder ESCALATEs"          "$(states)" "START MILESTONE MILESTONE MILESTONE ESCALATE "
expect "the ladder climbs"                      "$(tr '\n' ' ' <"$PI_CALLS")" "nan/deepseek-v4-flash nan/deepseek-v4-flash nan/glm5.3-flash "
expect "worker.diff includes new files"         "$(grep -c '^+++ b/done.txt' "$FHQ/logs/t/worker.diff")" "1"
expect "escalated work is left uncommitted"     "$(git -C "$R" log --oneline | wc -l | tr -d ' ')" "1"

fresh "" capped pass
foreman >/dev/null
expect "an output cap skips to the next rung"   "$(tr '\n' ' ' <"$PI_CALLS")" "nan/deepseek-v4-flash nan/glm5.3-flash "
expect "and says so"                            "$(grep -c 'attempt 1/3 pi:nan/deepseek-v4-flash FAIL .*output cap: no more pi:nan/deepseek-v4-flash tries' "$FHQ/STATUS.md") $(grep -c 'attempt 3/3 pi:nan/glm5.3-flash PASS' "$FHQ/STATUS.md")" "1 1"
fresh "" capped broken broken pass
MISTER_HANDY_LADDER="nan/a 1,nan/b 2,nan/c 1" foreman >/dev/null
expect "an older capped session does not skip"  "$(tr '\n' ' ' <"$PI_CALLS")" "nan/a nan/b nan/b nan/c "
fresh "" capped
expect "a cap on the last rung ESCALATEs"       "$(MISTER_HANDY_LADDER="nan/a 2" foreman | tr '\n' ' '; awk '$3 == "ESCALATE" { print $4, $5, $6, $7 }' "$FHQ/STATUS.md")" "exit 3 1 attempts failed (pi:nan/a);"

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
expect "REVISE gets one more worker round"      "$(tr '\n' ' ' <"$PI_CALLS")" "nan/deepseek-v4-flash reviewed nan/qwen3.6 nan/deepseek-v4-flash "
expect "the revised round is committed"         "$(git -C "$R" ls-files notes.txt) $(grep -c 'DONE.*review items applied' "$FHQ/STATUS.md")" "notes.txt 1"
fresh "" pass
echo PASS >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 foreman >/dev/null
expect "a review PASS is DONE"                  "$(awk '$3 == "DONE"' "$FHQ/STATUS.md" | grep -c 'review PASS')" "1"

fresh "" pass
echo PASS >"$PI_REVIEW"
printf 'REVISE\n1. rename x\nPASSES the tests\n' >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 MISTER_HANDY_LADDER="nan/glm5.3-flash 1" foreman >/dev/null
expect "a PASS-prefixed line does not reset REVISE" "$(grep -c 'MILESTONE review nan/qwen3.6 REVISE' "$FHQ/STATUS.md")" "1"
fresh "" pass breaks
printf 'REVISE\n1. something\n' >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 foreman >/dev/null
expect "a failed review round is rolled back"   "$(cat "$R/done.txt") $(ls "$R" | grep -cE 'junk|newdir') $(grep -c 'DONE.*review items not applied' "$FHQ/STATUS.md")" "ok 0 1"
fresh "" pass
: >"$PI_REVIEW"
MISTER_HANDY_REVIEW=nan/qwen3.6 foreman >/dev/null
expect "a silent reviewer is inconclusive"      "$(grep -c 'DONE.*review inconclusive' "$FHQ/STATUS.md")" "1"

fresh "" pass
MISTER_HANDY_ADVISOR=opus foreman >/dev/null
expect "the worker gets the advisor extension"  "$(grep -c -- "^$here/advisor.ts\$" "$PI_ARGS") $(grep -c 'You have an `advisor` tool' "$PI_LAST_PROMPT") $(grep -c -- '-e' "$PI_ARGS")" "1 1 1"
fresh "" pass
foreman >/dev/null
expect "without MISTER_HANDY_ADVISOR no extension is loaded" "$(grep -c advisor "$PI_ARGS") $(grep -c 'advisor' "$PI_LAST_PROMPT")" "0 0"
fresh "" pass
printf '10:00 advisor call 1/4 $0.0312 20s\n10:01 advisor call 2/4 $0.0188 15s\n' >"$tmp/adv.lines"
PI_ADVISOR_LINES=$tmp/adv.lines MISTER_HANDY_ADVISOR=opus foreman >/dev/null
expect "advisor calls show up in STATUS and DONE" "$(grep -c 'MILESTONE advisor call [12]/4 (\$0.0[32])' "$FHQ/STATUS.md") $(awk '$3 == "DONE"' "$FHQ/STATUS.md" | grep -c 'advisor 2 calls \$0.05')" "2 1"

fresh "" pass
echo stray >"$R/pre-existing.txt"
expect "a dirty tree is refused"                "$(foreman; states)" "exit 2
FAILED "
fresh "" pass
git -C "$R" checkout -qb main
expect "main is refused"                        "$(foreman >/dev/null; states)" "FAILED "
fresh "" pass
brief "Risk: low" "## Acceptance
Run the tests and check they pass"
expect "a prose Acceptance line is FAILED"      "$(foreman >/dev/null; grep -c 'FAILED acceptance line 1 is not a runnable command' "$FHQ/STATUS.md")" "1"
expect "and no worker ran"                      "$(cat "$PI_CALLS" 2>/dev/null | wc -l | tr -d ' ')" "0"

brief "Risk: low" "Scope: done.txt src/*
$ACC"
fresh "" outside revert
mkdir -p "$R/src" && echo x >"$R/src/x.py" && git -C "$R" add -A && git -C "$R" commit -qm src
foreman >/dev/null
expect "Scope globs reach nested paths"         "$(git -C "$R" ls-files src/sub/y.py)" "src/sub/y.py"
expect "out-of-scope files fail the attempt"    "$(states)" "START MILESTONE MILESTONE DONE "
expect "the Scope failure names the files"      "$(grep -c "FAIL 'Scope'" "$FHQ/STATUS.md") $(grep -c 'outside the brief.s Scope (done.txt src/\*): other.txt' "$PI_LAST_PROMPT")" "1 1"
brief "Risk: low" "$ACC"

fresh "" secret
expect "a secret in the diff ESCALATEs"         "$(foreman; grep -c 'ESCALATE possible secret in: config.py' "$FHQ/STATUS.md")" "exit 3
1"
expect "the secret is not committed or shown"   "$(git -C "$R" log --oneline | wc -l | tr -d ' ') $(grep -c abcd1234 "$FHQ/STATUS.md")" "1 0"
fresh "" config
foreman >/dev/null
expect "config code reading a token is not a secret" "$(states)" "START MILESTONE DONE "
fresh "" dotenv
foreman >/dev/null
expect "a .env file ESCALATEs"                  "$(grep -c 'ESCALATE possible secret in: .env.local' "$FHQ/STATUS.md")" "1"

fresh "" hang
MISTER_HANDY_PI_TIMEOUT=1 MISTER_HANDY_LADDER="nan/glm5.3-flash 1" foreman >/dev/null
expect "a pi timeout is named"                  "$(grep -c 'FAIL.*pi timed out' "$FHQ/STATUS.md")" "1"
expect "a timed-out worker's children die"      "$(kill -0 "$(cat "$PI_CHILD")" 2>/dev/null && echo alive || echo dead)" "dead"
fresh "" slow
MISTER_HANDY_HEARTBEAT=1 foreman >/dev/null
expect "a long attempt writes a heartbeat"      "$(grep -c 'MILESTONE still working: attempt 1/3' "$FHQ/STATUS.md" | awk '{ print ($1 > 0) }')" "1"

brief "Risk: low" "## Acceptance
grep -qx ok done.txt
test -f ok.txt
test -f not_ok.txt || true"
fresh "" edits-test
foreman >/dev/null
expect "DONE names Acceptance files it changed" "$(grep -c 'changed files the Acceptance runs: done.txt ok.txt' "$FHQ/STATUS.md")" "1"
brief "Risk: low" "$ACC"
fresh "node_modules" atl-and-edit
foreman >/dev/null
expect "a worker's own .gitignore edit is kept" "$(tr '\n' ' ' <"$R/.gitignore")" "node_modules logs/ "
fresh "" pass
expect "pi always runs without extensions"      "$(MISTER_HANDY_PI_FLAGS=--offline foreman >/dev/null; grep -c . "$PI_CALLS")" "1"
brief "Risk: low" "## Acceptance
./missing.sh"
fresh "" broken broken broken
expect "a missing path command stops at once"   "$(foreman; grep -c "FAILED acceptance not runnable: './missing.sh'" "$FHQ/STATUS.md"; grep -c . "$PI_CALLS")" "exit 2
1
1"
brief "Risk: low" "## Acceptance
bash run.sh"
fresh "" broken
expect "a missing script for bash stops at once" "$(foreman >/dev/null; grep -c "FAILED acceptance not runnable: 'run.sh'" "$FHQ/STATUS.md")" "1"
brief "Risk: low" "## Acceptance
./run.sh"
fresh "" broken
printf '#!/bin/sh\nexit 0\n' >"$R/run.sh" && git -C "$R" add run.sh && git -C "$R" commit -qm run
expect "a non-executable path command stops at once" "$(foreman >/dev/null; grep -c "FAILED acceptance not runnable: './run.sh'.*exit 126" "$FHQ/STATUS.md")" "1"
brief "Risk: low" "$ACC"
fresh "" ratelimited pass
foreman >/dev/null
expect "a 429 is retried without a ladder try"  "$(states)" "START MILESTONE MILESTONE DONE "
expect "the retry is the same attempt"          "$(grep -c 'attempt 1/3 pi:nan/deepseek-v4-flash rate-limited, retry 1' "$FHQ/STATUS.md") $(grep -c 'attempt 1/3 pi:nan/deepseek-v4-flash PASS' "$FHQ/STATUS.md")" "1 1"
expect "the slot is released"                   "$(ls "$tmp/slots/pi-nan" | wc -l | tr -d ' ')" "0"
fresh "" pass
sleep 4 & holder=$!
mkdir -p "$tmp/slots/pi-nan/1" && echo "$holder" >"$tmp/slots/pi-nan/1/pid"
MISTER_HANDY_NAN_SLOTS=1 foreman >/dev/null
expect "a busy machine waits for a NAN slot"    "$(states)" "START MILESTONE MILESTONE DONE "
expect "and says so once"                       "$(grep -c 'MILESTONE waiting for a pi:nan slot (1 busy' "$FHQ/STATUS.md")" "1"
fresh "" pass
mkdir -p "$tmp/slots/pi-nan/1" && echo 999999 >"$tmp/slots/pi-nan/1/pid"
MISTER_HANDY_NAN_SLOTS=1 foreman >/dev/null
expect "a dead holder's slot is reclaimed"      "$(states)" "START MILESTONE DONE "
fresh "" pass
sleep 4 & holder=$!
mkdir -p "$tmp/slots/pi-nan/1" && echo "$holder" >"$tmp/slots/pi-nan/1/pid"
MISTER_HANDY_SLOTS=5 MISTER_HANDY_NAN_SLOTS=1 foreman >/dev/null
expect "NAN_SLOTS still caps pi:nan"            "$(states) $(grep -c 'waiting for a pi:nan slot (1 busy' "$FHQ/STATUS.md")" "START MILESTONE MILESTONE DONE  1"
fresh "" pass
MISTER_HANDY_SLOTS=1 MISTER_HANDY_LADDER="claude:haiku 1" foreman >/dev/null
expect "a pi:nan holder does not block claude"  "$(states)" "START MILESTONE DONE "
wait "$holder" 2>/dev/null
mkdir -p "$tmp/slots/claude/1" && echo "$$" >"$tmp/slots/claude/1/pid"
fresh "" pass
expect "MISTER_HANDY_SLOTS caps claude"         "$(MISTER_HANDY_SLOTS=1 MISTER_HANDY_LADDER="claude:haiku 1" MISTER_HANDY_SLOT_POLL=1 perl -e 'alarm 3; exec @ARGV' bash "$here/foreman.sh" t "$B" "$FHQ" "$R" >/dev/null 2>&1; grep -c 'waiting for a claude slot' "$FHQ/STATUS.md")" "1"
rm -rf "$tmp/slots/claude/1"

fresh "" pass
MISTER_HANDY_ADVISOR=opus MISTER_HANDY_LADDER="claude:haiku 1" foreman >/dev/null
expect "a claude:haiku rung runs the claude runner" "$(tr '\n' ' ' <"$PI_CALLS")$(states)" "claude haiku START MILESTONE DONE "
expect "the claude worker is headless, no MCP, no session, no advisor" "$(grep -cxE -- '-p|--no-session-persistence|--strict-mcp-config|--permission-mode|Read,Edit,Write,Bash,Grep,Glob' "$CLAUDE_ARGS") $(grep -c 'advisor\.ts\|an .advisor. tool' "$CLAUDE_ARGS" "$PI_LAST_PROMPT" | awk -F: '{ s += $2 } END { print s }')" "6 0"
expect "the claude worker gets the brief"       "$(grep -c '^Write ok to done.txt.$' "$PI_LAST_PROMPT")" "1"
expect "the claude runner disables the Claude Code advisor" "$(grep -A1 -x -- '--settings' "$CLAUDE_ARGS" | tr '\n' ' ')" '--settings {"advisorModel":""} '
fresh "" pass
MISTER_HANDY_CLAUDE_ADVISOR=keep MISTER_HANDY_LADDER="claude:haiku 1" foreman >/dev/null
expect "MISTER_HANDY_CLAUDE_ADVISOR=keep leaves it on" "$(grep -c advisorModel "$CLAUDE_ARGS") $(states)" "0 START MILESTONE DONE "
fresh "" capped pass
MISTER_HANDY_LADDER="claude:haiku 2,claude:sonnet 1" foreman >/dev/null
expect "a claude max-turns cap skips to the next rung" "$(tr '\n' ' ' <"$PI_CALLS")$(grep -c 'output cap: no more claude:haiku tries' "$FHQ/STATUS.md")" "claude haiku claude sonnet 1"
fresh "" ratelimited pass
MISTER_HANDY_LADDER="claude:haiku 1" foreman >/dev/null
expect "a claude 429 is retried without a ladder try" "$(grep -c 'attempt 1/1 claude:haiku rate-limited, retry 1' "$FHQ/STATUS.md") $(states)" "1 START MILESTONE MILESTONE DONE "
fresh "" pass
MISTER_HANDY_LADDER="nan/x 1" foreman >/dev/null
expect "a bare nan/ line is a pi rung"          "$(tr '\n' ' ' <"$PI_CALLS")$(grep -c 'attempt 1/1 pi:nan/x PASS' "$FHQ/STATUS.md")" "nan/x 1"
fresh "" pass
expect "an unknown runner is FAILED"            "$(MISTER_HANDY_LADDER="codex:gpt 1" foreman; grep -c 'FAILED unknown runner in rung codex:gpt' "$FHQ/STATUS.md")" "exit 2
1"
fresh "" pass
echo PASS >"$PI_REVIEW"
MISTER_HANDY_REVIEW=claude:sonnet foreman >/dev/null
expect "a claude reviewer is read-only"         "$(tr '\n' ' ' <"$PI_CALLS")$(grep -cx 'Read,Grep,Glob' "$CLAUDE_ARGS") $(grep -c 'DONE.*review PASS' "$FHQ/STATUS.md")" "nan/deepseek-v4-flash claude sonnet 2 1"
expect "the claude reviewer runs without the Claude Code advisor too" "$(grep -cx '{"advisorModel":""}' "$CLAUDE_ARGS")" "1"
fresh "" pushy
foreman >/dev/null
expect "the worker cannot push or use gh"       "$(git -C "$tmp/origin.git" branch | wc -l | tr -d ' ') $(git -C "$R" ls-files gh-ran | wc -l | tr -d ' ')" "0 0"
expect "without PR: the foreman does not push"  "$(grep -c 'DONE .* on feat/t (local)' "$FHQ/STATUS.md")" "1"
fresh "" pass
brief "Risk: low
PR: ready main" "$ACC"
echo "https://github.com/o/r/pull/9" >"$tmp/pr-url"
foreman >/dev/null
expect "PR: pushes and opens the PR"            "$(git -C "$tmp/origin.git" branch | tr -d ' *') $(grep -c 'DONE https://github.com/o/r/pull/9' "$FHQ/STATUS.md")" "feat/t 1"
expect "the worker never sees PR:"              "$(grep -c '^PR:' "$PI_LAST_PROMPT")" "0"
brief "Risk: low" "$ACC"
fresh "" branchy
expect "a worker that switches branch ESCALATEs" "$(foreman >/dev/null; grep -c 'ESCALATE the worker left branch feat/t' "$FHQ/STATUS.md")" "1"

SV=$tmp/sv && mkdir -p "$SV"
cat >"$SV/STATUS.md" <<'EOT'
# append-only
08:30 hq DISPATCHED a
08:53 a DONE https://github.com/o/r/pull/1, acceptance passed on attempt 1/3 (nan/m1), review PASS
09:10 b MILESTONE advisor call 1/4 ($0.15)
09:12 b DONE abc on feat/b (local), acceptance passed on attempt 3/3 (nan/m2), review PASS, advisor 2 calls $0.37; logs /x
09:20 c DONE https://github.com/o/r/pull/2 e280862
09:30 d MILESTONE advisor call 1/4 ($0.20)
09:40 d ESCALATE 3 attempts failed (nan/m1 FAIL); advisor 1 calls $0.20; summary /x
EOT
sv() { bash "$here/savings.sh" "$SV" "$@" | awk '{$1=$1}1'; }
expect "savings: header"                        "$(sv | sed -n 1p)" "slug result model attempt claude baseline"
expect "savings: DONE without advisor"          "$(sv)" 'a DONE nan/m1 1/3 $0.00 $3.16'
expect "savings: DONE with advisor"             "$(sv)" 'b DONE nan/m2 3/3 $0.37 $3.16'
expect "savings: ESCALATE"                      "$(sv)" 'd ESCALATE - - $0.20 $3.16'
expect "savings: noise lines are ignored"       "$(sv | wc -l | tr -d ' ')" "5"
expect "savings: TOTAL"                         "$(sv | tail -n 1)" 'TOTAL - - - $0.57 $9.48 saving $8.91'
expect "savings: baseline override"             "$(MISTER_HANDY_BASELINE_USD=10 sv | tail -n 1)" 'TOTAL - - - $0.57 $30.00 saving $29.43'
expect "savings: no foreman rows"               "$(printf '# x\n' >"$tmp/sv0.md"; mkdir -p "$tmp/sv0" && cp "$tmp/sv0.md" "$tmp/sv0/STATUS.md"; bash "$here/savings.sh" "$tmp/sv0" | awk '{$1=$1}1' | tail -n 1)" 'TOTAL - - - $0.00 $0.00 saving $0.00'
expect "savings: missing STATUS exits 2"        "$(bash "$here/savings.sh" "$tmp/nope" 2>/dev/null; echo $?)" "2"

expect "the HQ note tells HQ to route code tasks" "$(MISTER_HANDY=hq CLAUDE_PROJECT_DIR=$tmp bash "$here/../../../hooks/role.sh" | grep -c 'run bin/route.sh, and launch what it prints')" "1"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failing"; exit 1; }
