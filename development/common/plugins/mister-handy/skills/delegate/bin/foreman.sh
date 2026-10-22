#!/bin/bash
# foreman.sh <slug> <brief> <hq dir> [worktree, default .]
# Runs a cheap worker on the brief, then its Acceptance commands from the worktree root. A failure
# goes back to the worker with the output appended, climbing the ladder (MISTER_HANDY_LADDER, else
# ~/.config/mister-handy/ladder, else ../ladder: "<runner>:<model> <tries>" per line, runner pi or claude,
# a bare "<provider>/<model>" is pi). Reports to <hq>/STATUS.md itself: START, one MILESTONE per
# attempt (and a heartbeat every 10 min), then DONE <PR url|sha>, ESCALATE <why> (HQ relaunches on
# Claude) or FAILED <why> (the brief or the worktree is not fit to start). Logs in <hq>/logs/<slug>/.
# Starts only on a clean feature branch. The worker cannot push or use gh; the foreman pushes and
# opens a PR only when the brief has "PR: ready|draft <base>". "Scope: <globs>" limits what it may
# change. MISTER_HANDY_REVIEW=<rung> adds one read-only reviewer pass; REVISE gets one more round.
# MISTER_HANDY_ADVISOR=<claude model> gives a pi worker an `advisor` tool (bin/advisor.ts) that sends its
# conversation to that model; up to MISTER_HANDY_ADVISOR_MAX (4) calls, each logged to <hq>/logs/<slug>/advisor.log.
# At most MISTER_HANDY_SLOTS (3) runs at once per user and provider (pi:<provider>, claude), machine-wide;
# MISTER_HANDY_NAN_SLOTS caps pi:nan. A run cut off by a rate limit (429) is retried after a backoff without
# using up a ladder try. A failed attempt that ended on the output cap (pi stopReason length, claude max
# turns or max tokens) skips that model's remaining tries.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
load_config
slug=${1:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
brief=${2:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
hq=${3:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
brief=$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")
hq=$(cd "$hq" && pwd)
logs=$hq/logs/$slug
pi_timeout=${MISTER_HANDY_PI_TIMEOUT:-1800}
check_timeout=${MISTER_HANDY_CHECK_TIMEOUT:-600}
pi_flags="-ne ${MISTER_HANDY_PI_FLAGS:-}"
conf_dir=${XDG_CONFIG_HOME:-$HOME/.config}/mister-handy
slot_root=${MISTER_HANDY_SLOT_DIR:-$HOME/.cache/mister-handy/slots}
slot=""
rate_limited='(^|[^0-9])429([^0-9]|$)|rate[ _-]?limit|too many requests|max_parallel|concurrent requests'

artifacts='(^|/)(__pycache__|node_modules|venv|\.venv|dist|build|target|coverage[^/]*|\.coverage|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|\.DS_Store|[^/]+\.egg-info)(/|$)|\.py[co]$'
secret_text='BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|(api[_-]?key|secret|token|passw(or)?d)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+=-]{12,}'
limit_pl='$t = shift; $p = fork; if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 } setpgrp($p, $p);
  $SIG{ALRM} = sub { kill "TERM", -$p; sleep 2; kill "KILL", -$p; exit 142 }; alarm $t;
  waitpid($p, 0); $rc = $?; alarm 0; kill "TERM", -$p; exit($rc & 127 ? 128 + ($rc & 127) : $rc >> 8)'

say() { echo "$(date +%H:%M) $slug $*" >>"$hq/STATUS.md"; }
card() { command -v orca >/dev/null && orca worktree set --worktree "path:$PWD" --comment "foreman: $1" --json >/dev/null 2>&1; }
limit() { perl -e "$limit_pl" "$@"; }
oneline() { tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //; s/ $//' | cut -c1-"${1:-120}"; }
redact() {
  perl -pe 's/((?:api[_-]?key|token|secret|passw(?:or)?d|authorization)\S*\s*[=:]\s*)\S+/$1<redacted>/gi;
    s/(Bearer\s+)\S+/$1<redacted>/gi; s/sk-[A-Za-z0-9_-]{12,}/sk-<redacted>/g; s/AKIA[0-9A-Z]{16}/AKIA<redacted>/g'
}
end() { say "$1 $2"; card "$1 $2"; exit "$3"; }
beat() { (while sleep "${MISTER_HANDY_HEARTBEAT:-600}"; do say "MILESTONE still working: $1"; done) 2>/dev/null & hb=$!; }
unbeat() { [ -z "${hb:-}" ] || { pkill -P "$hb" 2>/dev/null; kill "$hb" 2>/dev/null; hb=""; }; }
acquire() {
  local i pid waiting="" slots=${MISTER_HANDY_SLOTS:-3}
  local slot_dir=$slot_root/$(printf %s "$1" | tr -c 'A-Za-z0-9._-' -)
  [ "$1" != pi:nan ] || slots=${MISTER_HANDY_NAN_SLOTS:-$slots}
  mkdir -p "$slot_dir"
  while :; do
    i=1
    while [ "$i" -le "$slots" ]; do
      mkdir "$slot_dir/$i" 2>/dev/null && { echo $$ >"$slot_dir/$i/pid"; slot=$slot_dir/$i; return 0; }
      pid=$(cat "$slot_dir/$i/pid" 2>/dev/null)
      if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || { [ -z "$pid" ] && [ -n "$(find "$slot_dir/$i" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }; then
        mv "$slot_dir/$i" "$slot_dir/stale.$i.$$" 2>/dev/null && rm -rf "$slot_dir/stale.$i.$$"
        continue
      fi
      i=$((i + 1))
    done
    [ -n "$waiting" ] || say "MILESTONE waiting for a $1 slot ($slots busy in $slot_dir)"
    waiting=1
    sleep "${MISTER_HANDY_SLOT_POLL:-5}"
  done
}
release() { [ -z "$slot" ] || rm -rf "$slot"; slot=""; }
trap 'unbeat; release' EXIT

[ -f "$brief" ] || end FAILED "no brief at $brief" 2
cd "${4:-.}" 2>/dev/null && cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null ||
  end FAILED "not a git worktree: ${4:-.}" 2
mkdir -p "$logs/bin"
: >"$logs/advisor.log"
[ -n "$(brief_acceptance "$brief")" ] || end FAILED "brief has no Acceptance commands; route it to Claude" 2
lint=$(brief_lint "$brief" strict) || end FAILED "$lint" 2
pr=$(brief_pr "$brief")
base=$(git rev-parse HEAD)
branch=$(git branch --show-current)
case $branch in
  "" | main | master | "${pr#* }") end FAILED "not on a feature branch (${branch:-detached HEAD}); start from a fresh branch" 2 ;;
esac
[ -z "$(git status --porcelain)" ] || end FAILED "worktree not clean; the foreman commits only the worker's changes" 2

models=()
while read -r m n; do
  while [ "$n" -gt 0 ]; do models+=("$m"); n=$((n - 1)); done
done < <(ladder)
total=${#models[@]}
[ "$total" -gt 0 ] || end FAILED "empty ladder" 2
review_rung=""
[ -z "${MISTER_HANDY_REVIEW:-}" ] || review_rung=$(MISTER_HANDY_LADDER=$MISTER_HANDY_REVIEW ladder | awk '{ print $1; exit }')
for m in "${models[@]}" $review_rung; do
  case ${m%%:*} in
    pi | claude) command -v "${m%%:*}" >/dev/null || end ESCALATE "${m%%:*} not installed (ladder rung $m)" 3 ;;
    *) end FAILED "unknown runner in rung $m; use pi:<provider>/<model> or claude:<model>" 2 ;;
  esac
done

title=$(brief_title "$brief")
title=${title:-$slug}
scope=$(brief_scope "$brief")
had_atl=$([ -e .atl ] && echo 1)
had_gi=$([ -e .gitignore ] && echo 1)
[ -z "$had_gi" ] || cp .gitignore "$logs/gitignore.orig"
pi_lines='/?\.atl/?|# Local Pi runtime state'
printf '#!/bin/sh\necho "gh is disabled for cheap workers; the foreman opens the PR" >&2\nexit 1\n' >"$logs/bin/gh"
chmod +x "$logs/bin/gh"

clean_strays() {
  [ -n "$had_atl" ] || rm -rf .atl
  [ -f .gitignore ] && grep -qxE "$pi_lines" .gitignore || return 0
  [ -z "$had_gi" ] || ! grep -qxE "$pi_lines" "$logs/gitignore.orig" || return 0
  grep -vxE "$pi_lines" .gitignore >"$logs/gitignore.now"
  if [ -n "$had_gi" ] && [ "$(grep -v '^$' "$logs/gitignore.now")" = "$(grep -v '^$' "$logs/gitignore.orig")" ]; then
    cp "$logs/gitignore.orig" .gitignore
  elif [ -z "$had_gi" ] && ! grep -q . "$logs/gitignore.now"; then
    rm -f .gitignore
  else
    cp "$logs/gitignore.now" .gitignore
  fi
}

unrunnable() {
  local w a rest
  read -r w a rest <<<"$(sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' <<<"$1")"
  case $w in
    */*) [ -f "$w" ] && [ -x "$w" ] || { echo "$w"; return 0; } ;;
    bash | sh | zsh) case $a in "" | -*) ;; *) [ -f "$a" ] || { echo "$a"; return 0; } ;; esac ;;
    *) type -t "$w" >/dev/null || { echo "$w"; return 0; } ;;
  esac
  return 1
}

untracked() { git -c core.quotePath=false ls-files -o --exclude-standard; }
changed() { { git -c core.quotePath=false diff --name-only "$base"; untracked | grep -vE "$artifacts"; } | sort -u; }

advisor_rules='## Advisor
You have an `advisor` tool with no parameters. Calling it sends your whole conversation so far to a stronger model and returns its advice. Call it:
1. before substantive work, once you have oriented yourself (read the files you need), and before you write or edit anything;
2. when you are stuck: errors keep recurring or your approach is not converging;
3. when you believe the task is done, after the result is saved to disk and the Acceptance commands pass.
Give its advice serious weight. If you follow a step and it fails, or you have direct evidence (a file, a command output) that contradicts a specific claim, adapt; but do not silently switch: call the advisor again and say what you found so it can reconcile.'

adv_seen=0
adv_total=0
adv_sync() {
  local line n=0 c
  [ -f "$logs/advisor.log" ] || return 0
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -gt "$adv_seen" ] || continue
    c=$(sed -n 's/.* \$\([0-9.]*\) [0-9]*s$/\1/p' <<<"$line")
    adv_total=$(awk -v a="$adv_total" -v b="${c:-0}" 'BEGIN { printf "%.4f", a + b }')
    say "MILESTONE advisor call $(awk '{ print $4 }' <<<"$line") ($(awk -v c="${c:-0}" 'BEGIN { printf "$%.2f", c }'))"
  done <"$logs/advisor.log"
  adv_seen=$n
}
claude_total=0
claude_sync() {
  local c
  c=$(jq -r '.total_cost_usd // 0 | tostring' "$logs/claude.out" 2>/dev/null)
  case $c in '' | *[!0-9.]* | *.*.*) c=0 ;; esac
  claude_total=$(awk -v a="$claude_total" -v b="$c" 'BEGIN { printf "%.4f", a + b }')
}
adv_note() {
  adv_sync
  [ "$adv_seen" -eq 0 ] || printf ', advisor %s calls $%.2f' "$adv_seen" "$adv_total"
  claude_note
}
claude_note() { awk -v c="$claude_total" 'BEGIN { if (c > 0) printf ", claude $%.2f", c }'; }

sandboxed() {
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY -u CLAUDECODE PATH="$logs/bin:$PATH" \
    GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0=/dev/null \
    GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1= GIT_TERMINAL_PROMPT=0 \
    MISTER_HANDY_ADVISOR_LOG="$logs/advisor.log" \
    perl -e "$limit_pl" "$pi_timeout" "$@"
}

run_worker() {
  local runner=$1 model=$2 pf=$3 ro=${4:-} rc args=() tools=Read,Edit,Write,Bash,Grep,Glob session key
  stop=""
  case $runner in
    pi)
      if [ -n "$ro" ]; then
        args=(--no-session --tools read,grep,find,ls)
        [ ! -s "$logs/judge.md" ] || args+=(--append-system-prompt "$logs/judge.md")
      else
        args=(--session-dir "$logs/sessions")
        [ -z "${MISTER_HANDY_ADVISOR:-}" ] || args+=(-e "$here/advisor.ts")
        ls "$logs/sessions" >"$logs/sessions.before" 2>/dev/null
      fi
      key=pi
      case $model in */*) key=pi:${model%%/*} ;; esac
      acquire "$key"
      sandboxed pi -p $pi_flags "${args[@]}" --model "$model" "$(cat "$pf")" </dev/null
      rc=$?
      release
      clean_strays
      [ -z "$ro" ] || return "$rc"
      session=$(ls "$logs/sessions" 2>/dev/null | grep '\.jsonl$' | tail -n 1)
      [ -z "$session" ] || grep -qxF "$session" "$logs/sessions.before" ||
        stop=$(grep -o '"stopReason":"[A-Za-z]*"' "$logs/sessions/$session" | tail -n 1 | cut -d'"' -f4)
      ;;
    claude)
      [ -z "$ro" ] || tools=Read,Grep,Glob
      [ -z "$ro" ] || [ ! -s "$logs/judge.md" ] || args=(--append-system-prompt-file "$logs/judge.md")
      [ "${MISTER_HANDY_CLAUDE_ADVISOR:-}" = keep ] || args+=(--settings '{"advisorModel":""}')
      acquire claude
      sandboxed claude -p --model "$model" --output-format json --no-session-persistence --strict-mcp-config \
        --tools "$tools" --allowedTools "$tools" --permission-mode dontAsk \
        --max-turns "${MISTER_HANDY_CLAUDE_MAX_TURNS:-100}" "${args[@]}" <"$pf" >"$logs/claude.out"
      rc=$?
      release
      claude_sync
      cat "$logs/claude.out"
      [ -n "$ro" ] || stop=$(jq -r 'if .stop_reason == "max_tokens" or .subtype == "error_max_turns" then "length" else .subtype // empty end' "$logs/claude.out" 2>/dev/null)
      [ "$rc" -ne 0 ] || ! jq -e '.is_error == true' "$logs/claude.out" >/dev/null 2>&1 || rc=1
      ;;
  esac
  return "$rc"
}

work() {
  local pf=$logs/$1.prompt.md
  {
    echo "You are working in the git worktree $PWD, branch $branch. Do the task in the brief below, here only."
    echo "The task is accepted only when every command under Acceptance exits 0, run from this directory. Run them yourself before you finish."
    echo "Do not push, open pull requests, switch branches, rewrite history, write to any STATUS.md or _hq folder, or touch files outside this worktree. You need not commit."
    echo
    brief_without "$brief" Reporting | grep -v '^PR:'
    [ -z "${MISTER_HANDY_ADVISOR:-}" ] || [ "${2%%:*}" != pi ] || printf '\n%s\n' "$advisor_rules"
    [ -z "$3" ] || printf '\n%s\n' "$3"
  } >"$pf"
  beat "attempt $attempt/$total $2"
  local retry=0 pause run=$pf
  runner=${2%%:*}
  while :; do
    run_worker "$runner" "${2#*:}" "$run" >"$logs/$1.$runner.log" 2>&1
    worker_rc=$?
    [ "$worker_rc" -ne 0 ] && [ "$retry" -lt "${MISTER_HANDY_RATE_RETRIES:-5}" ] &&
      tail -n 5 "$logs/$1.$runner.log" | grep -qiE "$rate_limited" || break
    retry=$((retry + 1))
    pause=$(( ${MISTER_HANDY_RATE_BACKOFF:-60} << (retry - 1) ))
    [ "$pause" -le 600 ] || pause=600
    mv "$logs/$1.$runner.log" "$logs/$1.$runner.rate-limited-$retry.log"
    say "MILESTONE attempt $attempt/$total $2 rate-limited, retry $retry in ${pause}s (does not use a ladder try)"
    sleep "$pause"
    run=$logs/$1.retry.prompt.md
    { cat "$pf"; printf '\n\nA previous run of this attempt was cut off by a rate limit; your changes so far are in the tree. Carry on.\n'; } >"$run"
  done
  unbeat
  adv_sync
  [ "$(git branch --show-current)" = "$branch" ] && git merge-base --is-ancestor "$base" HEAD ||
    end ESCALATE "the worker left branch $branch or rewrote its history$(claude_note); check $PWD by hand" 3
}

check() {
  local alog=$logs/$1.accept.log cmd f n out=""
  local clean_env=()
  while IFS= read -r n; do
    case $n in
      MISTER_HANDY_* | GIT_CONFIG_COUNT | GIT_CONFIG_KEY_* | GIT_CONFIG_VALUE_* | GIT_TERMINAL_PROMPT)
        clean_env+=(-u "$n") ;;
    esac
  done < <(compgen -e)
  : >"$alog"
  if [ -n "$scope" ]; then
    set -f
    while IFS= read -r f; do
      for g in $scope; do case $f in $g) continue 2 ;; esac; done
      out="$out $f"
    done < <(changed)
    set +f
    [ -z "$out" ] || {
      failed_cmd=Scope failed_rc=1
      failure="These changed files are outside the brief's Scope ($scope):$out. Revert them."
      echo "$failure" >"$alog"
      return 1
    }
  fi
  untracked | grep -vE "$artifacts" >"$logs/untracked"
  beat "acceptance checks, $1"
  while IFS= read -r cmd; do
    echo "\$ $cmd" >>"$alog"
    limit "$check_timeout" env "${clean_env[@]}" bash -c "$cmd" >>"$alog" 2>&1 </dev/null
    failed_rc=$?
    [ "$failed_rc" -eq 0 ] || { unbeat; failed_cmd=$cmd; failure=$(tail -n 80 "$alog"); return 1; }
  done < <(brief_acceptance "$brief")
  unbeat
}

commit() {
  local f hits=""
  git add -u || return 1
  while IFS= read -r f; do [ ! -e "$f" ] || git add -- "$f" || return 1; done <"$logs/untracked"
  while IFS= read -r f; do
    case $f in *.env.example | *.env.sample | *.env.template) ;; .env* | */.env*) hits="$hits $f"; continue ;; esac
    git diff --cached -U0 "$base" -- "$f" | grep '^+' | grep -qiE "$secret_text" && hits="$hits $f"
  done < <(git -c core.quotePath=false diff --cached --name-only "$base")
  [ -z "$hits" ] || { git reset -q; end ESCALATE "possible secret in:$hits$(claude_note); nothing committed, check $PWD by hand" 3; }
  git diff --cached --quiet || git commit -qm "$title" >>"$logs/commit.log" 2>&1
}

review() {
  local judge=${MISTER_HANDY_JUDGE:-$conf_dir/judge.md}
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } fm { next } /^## Review ledger/ { exit } { print }' \
    "$judge" >"$logs/judge.md" 2>/dev/null
  printf '%s\n\n%s\n\n## The change (git diff %s...HEAD)\n%s\n' \
    "Review this change in $PWD against the brief below. Ignore any output format in your system prompt. End with one line that is exactly PASS, or REVISE followed by numbered items, one per line, each a concrete fix." \
    "$(brief_without "$brief" Reporting | grep -v '^PR:')" "$base" "$(git diff "$base"...HEAD | head -c 200000)" >"$logs/review.prompt.md"
  run_worker "${review_rung%%:*}" "${review_rung#*:}" "$logs/review.prompt.md" read-only >"$logs/review.log" 2>&1
  [ "${review_rung%%:*}" != claude ] || jq -r '.result // empty' "$logs/claude.out" >"$logs/review.log" 2>/dev/null
  awk '{ l = $0; gsub(/^[*`[:space:]]+|[*`[:space:]]+$/, "", l) }
    l == "PASS" { v = "PASS"; on = 0; items = ""; next }
    l ~ /^REVISE([[:space:]:]|$)/ { v = l; on = 1; items = ""; next }
    on && NF { items = items $0 "\n" }
    END { if (v == "PASS") print v; else if (v != "") printf "%s\n%s", v, items }' "$logs/review.log" | head -c 4000
}

summary=$logs/summary.md
echo "# $slug: $title (base $base, branch $branch)" >"$summary"
say "START foreman on $branch, ladder ${models[*]}, $(brief_acceptance "$brief" | wc -l | tr -d ' ') acceptance commands, logs $logs"

failure=""
attempt=0
passed=""
capped=""
ran=""
for model in "${models[@]}"; do
  attempt=$((attempt + 1))
  [ "$model" != "$capped" ] || continue
  ran="$ran $model"
  card "attempt $attempt/$total $model"
  started=$SECONDS
  extra=""
  [ -z "$failure" ] || extra="## Previous attempt failed
Your changes from the previous attempt are still in the tree. The check \`$failed_cmd\` exited $failed_rc:
\`\`\`
$failure
\`\`\`
Fix what made it fail."
  work "attempt-$attempt" "$model" "$extra"
  secs=$((SECONDS - started))
  timed=$([ "$worker_rc" -eq 142 ] && echo ", $runner timed out")
  if check "attempt-$attempt"; then
    printf '\n## Attempt %s/%s %s: PASS (%ss, %s exit %s%s)\n' "$attempt" "$total" "$model" "$secs" "$runner" "$worker_rc" "${stop:+, stop $stop}" >>"$summary"
    say "MILESTONE attempt $attempt/$total $model PASS (${secs}s$timed)"
    commit || end FAILED "acceptance passed but the commit failed, see $logs/commit.log" 2
    passed=1
    break
  fi
  case $failed_rc in
    126 | 127) bad=$(unrunnable "$failed_cmd") &&
      end FAILED "acceptance not runnable: '$bad' is missing or not executable after attempt $attempt (exit $failed_rc); fix the brief or launch Claude" 2 ;;
  esac
  [ "$failed_rc" -ne 142 ] || timed="$timed, acceptance timed out"
  [ "$stop" != length ] || { capped=$model; timed="$timed, output cap: no more $model tries"; }
  printf '\n## Attempt %s/%s %s: FAIL (%ss, %s exit %s%s)\n`%s` exited %s:\n```\n%s\n```\n' \
    "$attempt" "$total" "$model" "$secs" "$runner" "$worker_rc" "${stop:+, stop $stop}" "$failed_cmd" "$failed_rc" "$(tail -n 40 <<<"$failure" | redact)" >>"$summary"
  say "MILESTONE attempt $attempt/$total $model FAIL '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc (${secs}s$timed), log $logs/attempt-$attempt.accept.log"
done
[ -n "$passed" ] || {
  git add -A -N . 2>/dev/null
  git diff "$base" >"$logs/worker.diff" 2>/dev/null
  git reset -q 2>/dev/null
  set -- $ran
  end ESCALATE "$# attempts failed ($*); last: '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc$(adv_note); worker changes left uncommitted in $PWD (git status --short; diff with new files in $logs/worker.diff); summary $summary" 3
}

sha=$(git rev-parse --short HEAD)
note=""
if [ -n "${MISTER_HANDY_REVIEW:-}" ]; then
  review >"$logs/verdict.txt"
  verdict=$(<"$logs/verdict.txt")
  case $verdict in
    PASS) note=", review PASS" ;;
    REVISE*)
      say "MILESTONE review $MISTER_HANDY_REVIEW REVISE $(sed -n '2,$p' <<<"$verdict" | grep -c .) items, one more round on $model"
      untracked | sort >"$logs/untracked.before-review"
      work review-round "$model" "## A reviewer asked for these changes
$verdict
Make them, keeping every Acceptance command passing."
      if check review-round && commit; then
        sha=$(git rev-parse --short HEAD)
        note=", review items applied"
      else
        git reset -q --hard "$sha"
        untracked | sort | comm -13 "$logs/untracked.before-review" - |
          while IFS= read -r f; do rm -f -- "$f"; rmdir -p "$(dirname "$f")" 2>/dev/null; done
        note=", review items not applied (checks failed after them, see $logs/review-round.accept.log)"
      fi
      ;;
    *) note=", review inconclusive (see $logs/review.log)" ;;
  esac
fi

[ "$(git rev-parse HEAD)" != "$base" ] || note="$note, no changes were needed"
touched=""
acc=$(brief_section "$brief" Acceptance)
while IFS= read -r f; do
  grep -qwF -- "$f" <<<"$acc" || grep -qwF -- "$(basename "$f")" <<<"$acc" && touched="$touched $f"
done < <(git -c core.quotePath=false diff --name-only "$base" HEAD)
[ -z "$touched" ] || note="$note; changed files the Acceptance runs:$touched"
where="$sha on $branch (local)"
if [ -n "$pr" ] && [ "$(git rev-parse HEAD)" != "$base" ]; then
  set -- $pr
  draft=$([ "$1" = draft ] && echo --draft)
  if git push -q -u origin HEAD >>"$logs/pr.log" 2>&1; then
    where="$sha on $branch (pushed)"
    url=$(gh pr create $draft --base "$2" --head "$branch" --title "$title" \
      --body "Implemented by a cheap worker ($model, attempt $attempt/$total) under mister-handy's foreman; every Acceptance command in the brief passed.
$acc" 2>>"$logs/pr.log" | tail -n 1)
  fi
  case ${url:-} in
    https://*) where="$url ($sha)" ;;
    *) note="$note, push/PR failed (see $logs/pr.log)" ;;
  esac
fi
end DONE "$where, acceptance passed on attempt $attempt/$total ($model)$note$(adv_note); logs $logs" 0
