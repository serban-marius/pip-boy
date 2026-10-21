#!/bin/bash
# foreman.sh <slug> <brief> <hq dir> [worktree, default .]
# Runs a cheap pi worker on the brief, then its Acceptance commands from the worktree root. A failure
# goes back to the worker with the output appended, climbing the ladder (MISTER_HANDY_LADDER, else
# ../ladder: "<model> <tries>" per line). Reports to <hq>/STATUS.md itself: START, one MILESTONE per
# attempt, then DONE <PR url|sha>, ESCALATE <why> (HQ relaunches on Claude) or FAILED <why>.
# Logs in <hq>/logs/<slug>/. Pushes and opens a PR only when the brief has "PR: ready|draft <base>".
# MISTER_HANDY_REVIEW=<model> adds one read-only reviewer pass; REVISE items get one more worker round.

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
pi_flags=${MISTER_HANDY_PI_FLAGS:--ne}

say() { echo "$(date +%H:%M) $slug $*" >>"$hq/STATUS.md"; }
card() { command -v orca >/dev/null && orca worktree set --worktree "path:$PWD" --comment "foreman: $1" --json >/dev/null 2>&1; }
limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }
oneline() { tr '\n\t' '  ' | tr -s ' ' | cut -c1-"${1:-120}"; }
end() { say "$1 $2"; card "$1 $2"; exit "$3"; }

[ -f "$brief" ] || end FAILED "no brief at $brief" 2
cd "${4:-.}" 2>/dev/null && cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null ||
  end FAILED "not a git worktree: ${4:-.}" 2
mkdir -p "$logs"
[ -n "$(brief_acceptance "$brief")" ] || end FAILED "brief has no Acceptance commands; route it to Claude" 2
command -v pi >/dev/null || end ESCALATE "pi not installed" 3

models=()
while read -r m n; do
  while [ "$n" -gt 0 ]; do models+=("$m"); n=$((n - 1)); done
done < <(ladder)
total=${#models[@]}
[ "$total" -gt 0 ] || end FAILED "empty ladder" 2

base=$(git rev-parse HEAD)
branch=$(git branch --show-current)
title=$(brief_title "$brief")
title=${title:-$slug}
had_atl=$([ -e .atl ] && echo 1)
had_gi=$([ -e .gitignore ] && echo 1)
gi_atl=$(grep -sxE '/?\.atl/?' .gitignore)

clean_strays() {
  [ -n "$had_atl" ] || rm -rf .atl
  if [ -f .gitignore ] && [ -z "$gi_atl" ] && grep -qxE '/?\.atl/?' .gitignore; then
    grep -vxE '/?\.atl/?' .gitignore >.gitignore.foreman
    mv .gitignore.foreman .gitignore
    [ -n "$had_gi" ] || [ -s .gitignore ] || rm -f .gitignore
  fi
}

work() {
  local pf=$logs/$1.prompt.md
  {
    echo "You are working in the git worktree $PWD, branch $branch. Do the task in the brief below, here only."
    echo "The task is accepted only when every command under Acceptance exits 0, run from this directory. Run them yourself before you finish."
    echo "Do not push, open pull requests, write to any STATUS.md or _hq folder, or touch files outside this worktree. You need not commit."
    echo
    brief_without "$brief" Reporting
    [ -z "$3" ] || printf '\n%s\n' "$3"
  } >"$pf"
  limit "$pi_timeout" pi -p $pi_flags --session-dir "$logs/sessions" --model "$2" "$(cat "$pf")" \
    >"$logs/$1.pi.log" 2>&1 </dev/null
  pi_rc=$?
  clean_strays
}

check() {
  local alog=$logs/$1.accept.log cmd
  : >"$alog"
  git -c core.quotePath=false ls-files -o --exclude-standard |
    grep -vE '(^|/)(__pycache__|node_modules|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.DS_Store)(/|$)|\.py[co]$' >"$logs/untracked"
  while IFS= read -r cmd; do
    echo "\$ $cmd" >>"$alog"
    limit "$check_timeout" bash -c "$cmd" >>"$alog" 2>&1 </dev/null
    failed_rc=$?
    [ "$failed_rc" -eq 0 ] || { failed_cmd=$cmd; failure=$(tail -n 80 "$alog"); return 1; }
  done < <(brief_acceptance "$brief")
}

commit() {
  git add -u || return 1
  while IFS= read -r f; do [ ! -e "$f" ] || git add -- "$f" || return 1; done <"$logs/untracked"
  git diff --cached --quiet || git commit -qm "$title" >>"$logs/commit.log" 2>&1
}

review() {
  local judge=${MISTER_HANDY_JUDGE:-$HOME/.pi/agent/agents/jd-judge-a.md}
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } fm { next } /^## Review ledger/ { exit } { print }' \
    "$judge" >"$logs/judge.md" 2>/dev/null
  limit "$pi_timeout" pi -p $pi_flags --no-session --tools read,grep,find,ls --model "$MISTER_HANDY_REVIEW" \
    --append-system-prompt "$logs/judge.md" \
    "Review this change in $PWD against the brief below. Ignore any output format in your system prompt. End with one line that is exactly PASS, or REVISE followed by numbered items, one per line, each a concrete fix.

$(brief_without "$brief" Reporting)

## The change (git diff $base...HEAD)
$(git diff "$base"...HEAD | head -c 200000)" >"$logs/review.log" 2>&1 </dev/null
  awk '/^(PASS|REVISE)/ { v = $0; on = ($1 == "REVISE") ; items = ""; next } on && NF { items = items $0 "\n" } END { if (v ~ /^REVISE/) printf "%s\n%s", v, items }' "$logs/review.log"
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
Your changes from the previous attempt are still in the tree. The acceptance check \`$failed_cmd\` exited $failed_rc:
\`\`\`
$failure
\`\`\`
Fix what made it fail."
  work "attempt-$attempt" "$model" "$extra"
  secs=$((SECONDS - started))
  if check "attempt-$attempt"; then
    printf '\n## Attempt %s/%s %s: PASS (%ss, pi exit %s)\n' "$attempt" "$total" "$model" "$secs" "$pi_rc" >>"$summary"
    say "MILESTONE attempt $attempt/$total $model PASS (${secs}s)"
    commit || end FAILED "acceptance passed but the commit failed, see $logs/commit.log" 2
    break
  fi
  last=$(grep -v '^[[:space:]]*$' <<<"$failure" | tail -n 1 | oneline 100)
  printf '\n## Attempt %s/%s %s: FAIL (%ss, pi exit %s)\n`%s` exited %s:\n```\n%s\n```\n' \
    "$attempt" "$total" "$model" "$secs" "$pi_rc" "$failed_cmd" "$failed_rc" "$(tail -n 40 <<<"$failure")" >>"$summary"
  say "MILESTONE attempt $attempt/$total $model FAIL '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc (${secs}s): $last"
  [ "$attempt" -lt "$total" ] || {
    git diff "$base" >"$logs/worker.diff" 2>/dev/null
    end ESCALATE "$total attempts failed (${models[*]}); last: '$(oneline 60 <<<"$failed_cmd")' exit $failed_rc; worker changes left uncommitted in $PWD; summary $summary" 3
  }
done

sha=$(git rev-parse --short HEAD)
note=""
if [ -n "${MISTER_HANDY_REVIEW:-}" ]; then
  verdict=$(review)
  if [ -n "$verdict" ]; then
    say "MILESTONE review $MISTER_HANDY_REVIEW REVISE $(sed -n '2,$p' <<<"$verdict" | wc -l | tr -d ' ') items, one more round on $model"
    work review-round "$model" "## A reviewer asked for these changes
$verdict
Make them, keeping every Acceptance command passing."
    if check review-round && commit; then
      sha=$(git rev-parse --short HEAD)
      note=", review items applied"
    else
      git reset -q --hard "$sha" && git clean -qfd
      note=", review items not applied (acceptance failed after them, see $logs/review-round.accept.log)"
    fi
  else
    note=", review PASS"
  fi
fi

[ "$(git rev-parse HEAD)" != "$base" ] || note="$note, no changes were needed"
where="$sha on $branch (local)"
pr=$(brief_pr "$brief")
if [ -n "$pr" ] && [ "$(git rev-parse HEAD)" != "$base" ]; then
  set -- $pr
  draft=$([ "$1" = draft ] && echo --draft)
  git push -q -u origin HEAD >>"$logs/pr.log" 2>&1 &&
    url=$(gh pr create $draft --base "$2" --head "$branch" --title "$title" \
      --body "Implemented by a cheap worker ($model, attempt $attempt/$total) under mister-handy's foreman; every Acceptance command in the brief passed.
$(brief_section "$brief" Acceptance)" 2>>"$logs/pr.log" | tail -n 1)
  case ${url:-} in
    https://*) where="$url ($sha)" ;;
    *) note="$note, push/PR failed (see $logs/pr.log)" ;;
  esac
fi
end DONE "$where, acceptance passed on attempt $attempt/$total ($model)$note; logs $logs" 0
