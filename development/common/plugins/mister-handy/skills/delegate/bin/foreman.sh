#!/bin/bash
# foreman.sh <slug> <brief> <hq dir> [worktree, default .]
# Runs a cheap pi worker on the brief, then its Acceptance commands from the worktree root. A failure
# goes back to the worker with the output appended, climbing the ladder (MISTER_HANDY_LADDER, else
# ../ladder: "<model> <tries>" per line). Reports to <hq>/STATUS.md itself: START, one MILESTONE per
# attempt (and a heartbeat every 10 min), then DONE <PR url|sha>, ESCALATE <why> (HQ relaunches on
# Claude) or FAILED <why> (the brief or the worktree is not fit to start). Logs in <hq>/logs/<slug>/.
# Starts only on a clean feature branch. The worker cannot push or use gh; the foreman pushes and
# opens a PR only when the brief has "PR: ready|draft <base>". "Scope: <globs>" limits what it may
# change. MISTER_HANDY_REVIEW=<model> adds one read-only reviewer pass; REVISE gets one more round.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
slug=${1:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
brief=${2:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
hq=${3:?usage: foreman.sh <slug> <brief> <hq dir> [worktree]}
brief=$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")
hq=$(cd "$hq" && pwd)
logs=$hq/logs/$slug
pi_timeout=${MISTER_HANDY_PI_TIMEOUT:-1800}
check_timeout=${MISTER_HANDY_CHECK_TIMEOUT:-600}
pi_flags="-ne ${MISTER_HANDY_PI_FLAGS:-}"
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
trap unbeat EXIT

[ -f "$brief" ] || end FAILED "no brief at $brief" 2
cd "${4:-.}" 2>/dev/null && cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null ||
  end FAILED "not a git worktree: ${4:-.}" 2
mkdir -p "$logs/bin"
[ -n "$(brief_acceptance "$brief")" ] || end FAILED "brief has no Acceptance commands; route it to Claude" 2
lint=$(brief_lint "$brief" strict) || end FAILED "$lint" 2
pr=$(brief_pr "$brief")
base=$(git rev-parse HEAD)
branch=$(git branch --show-current)
case $branch in
  "" | main | master | "${pr#* }") end FAILED "not on a feature branch (${branch:-detached HEAD}); start from a fresh branch" 2 ;;
esac
[ -z "$(git status --porcelain)" ] || end FAILED "worktree not clean; the foreman commits only the worker's changes" 2
command -v pi >/dev/null || end ESCALATE "pi not installed" 3

models=()
while read -r m n; do
  while [ "$n" -gt 0 ]; do models+=("$m"); n=$((n - 1)); done
done < <(ladder)
total=${#models[@]}
[ "$total" -gt 0 ] || end FAILED "empty ladder" 2

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

pi_run() {
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY PATH="$logs/bin:$PATH" \
    GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0=/dev/null \
    GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1= GIT_TERMINAL_PROMPT=0 \
    perl -e "$limit_pl" "$pi_timeout" pi -p $pi_flags "$@" </dev/null
}

work() {
  local pf=$logs/$1.prompt.md
  {
    echo "You are working in the git worktree $PWD, branch $branch. Do the task in the brief below, here only."
    echo "The task is accepted only when every command under Acceptance exits 0, run from this directory. Run them yourself before you finish."
    echo "Do not push, open pull requests, switch branches, rewrite history, write to any STATUS.md or _hq folder, or touch files outside this worktree. You need not commit."
    echo
    brief_without "$brief" Reporting | grep -v '^PR:'
    [ -z "$3" ] || printf '\n%s\n' "$3"
  } >"$pf"
  beat "attempt $attempt/$total $2"
  pi_run --session-dir "$logs/sessions" --model "$2" "$(cat "$pf")" >"$logs/$1.pi.log" 2>&1
  pi_rc=$?
  unbeat
  clean_strays
  [ "$(git branch --show-current)" = "$branch" ] && git merge-base --is-ancestor "$base" HEAD ||
    end ESCALATE "the worker left branch $branch or rewrote its history; check $PWD by hand" 3
}

check() {
  local alog=$logs/$1.accept.log cmd f out=""
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
    limit "$check_timeout" bash -c "$cmd" >>"$alog" 2>&1 </dev/null
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
  [ -z "$hits" ] || { git reset -q; end ESCALATE "possible secret in:$hits; nothing committed, check $PWD by hand" 3; }
  git diff --cached --quiet || git commit -qm "$title" >>"$logs/commit.log" 2>&1
}

review() {
  local judge=${MISTER_HANDY_JUDGE:-$HOME/.pi/agent/agents/jd-judge-a.md}
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } fm { next } /^## Review ledger/ { exit } { print }' \
    "$judge" >"$logs/judge.md" 2>/dev/null
  pi_run --no-session --tools read,grep,find,ls --model "$MISTER_HANDY_REVIEW" \
    --append-system-prompt "$logs/judge.md" \
    "Review this change in $PWD against the brief below. Ignore any output format in your system prompt. End with one line that is exactly PASS, or REVISE followed by numbered items, one per line, each a concrete fix.

$(brief_without "$brief" Reporting | grep -v '^PR:')

## The change (git diff $base...HEAD)
$(git diff "$base"...HEAD | head -c 200000)" >"$logs/review.log" 2>&1
  clean_strays
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
for model in "${models[@]}"; do
  attempt=$((attempt + 1))
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
  timed=$([ "$pi_rc" -eq 142 ] && echo ", pi timed out")
  if check "attempt-$attempt"; then
    printf '\n## Attempt %s/%s %s: PASS (%ss, pi exit %s)\n' "$attempt" "$total" "$model" "$secs" "$pi_rc" >>"$summary"
    say "MILESTONE attempt $attempt/$total $model PASS (${secs}s$timed)"
    commit || end FAILED "acceptance passed but the commit failed, see $logs/commit.log" 2
    break
  fi
  case $failed_rc in
    126 | 127) bad=$(unrunnable "$failed_cmd") &&
      end FAILED "acceptance not runnable: '$bad' is missing or not executable after attempt $attempt (exit $failed_rc); fix the brief or launch Claude" 2 ;;
  esac
  [ "$failed_rc" -ne 142 ] || timed="$timed, acceptance timed out"
  printf '\n## Attempt %s/%s %s: FAIL (%ss, pi exit %s)\n`%s` exited %s:\n```\n%s\n```\n' \
    "$attempt" "$total" "$model" "$secs" "$pi_rc" "$failed_cmd" "$failed_rc" "$(tail -n 40 <<<"$failure" | redact)" >>"$summary"
  say "MILESTONE attempt $attempt/$total $model FAIL '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc (${secs}s$timed), log $logs/attempt-$attempt.accept.log"
  [ "$attempt" -lt "$total" ] || {
    git add -A -N . 2>/dev/null
    git diff "$base" >"$logs/worker.diff" 2>/dev/null
    git reset -q 2>/dev/null
    end ESCALATE "$total attempts failed (${models[*]}); last: '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc; worker changes left uncommitted in $PWD (git status --short; diff with new files in $logs/worker.diff); summary $summary" 3
  }
done

sha=$(git rev-parse --short HEAD)
note=""
if [ -n "${MISTER_HANDY_REVIEW:-}" ]; then
  verdict=$(review)
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
end DONE "$where, acceptance passed on attempt $attempt/$total ($model)$note; logs $logs" 0
