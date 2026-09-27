#!/usr/bin/env bash
# vats: verifiers by cadence (pip-boy plugin). Runs as two Claude Code hooks:
#   PostToolUse(Edit|Write) -> vats.sh edit      PreToolUse(Bash) -> vats.sh commit
# Every check that runs is logged to ~/.claude/vats/log.jsonl; `vats.sh stats [days]` says whether the rules earn their keep.
# Contract: exit 0 = silent pass. exit 2 + stderr = on edit, Claude gets the failure as a reminder; on commit, the commit is blocked.
#
# Personal mode (default): the plugin's hooks/hooks.json runs this file as shipped. The checks for each repo live in
#   ~/.claude/vats/<repo-name>.sh, which defines on_edit/on_commit. Repos without a rules file are left alone.
# Team mode: a copy of this file is committed at <repo>/.claude/hooks/vats.sh with on_edit/on_commit filled in below.
# See RUNBOOK.md.

set -u
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
command -v jq >/dev/null || { echo "vats: jq not found, verifiers are OFF" >&2; exit 1; }
log="${VATS_HOME:-$HOME/.claude/vats}/log.jsonl" # one line per check that ran; `vats.sh stats` reads it

# Is this harness earning its keep? A rule that never fails is dead weight, fail>pass is the agent fixing itself
# (an interruption you didn't have), fail>fail is a rule it can't satisfy. It can't tell a real catch from a false alarm.
stats() { # $1 = days back (default 30)
  [ -s "$log" ] || { echo "vats: nothing logged yet ($log)"; exit 0; }
  jq -rs --argjson since "$(( $(date +%s) - ${1:-30} * 86400 ))" '
    def n(f): map(select(f)) | length;
    map(select(.ts >= $since)) as $l
    | [$l | group_by([.session, .mode, .file])[] | map(.result) | map(select(. != "skip"))] as $seqs
    | [$seqs[] | . as $r | range(1; $r | length) | $r[. - 1] + ">" + $r[.]] as $steps
    | "runs (repo mode: total / fail / skip, time spent)",
      ($l | group_by([.repo, .mode])[] | "  \(.[0].repo) \(.[0].mode): \(length) / \(n(.result == "fail")) / \(n(.result == "skip")), \(map(.ms) | add / 1000 | floor)s"),
      "after a fail",
      "  fixed by the agent (fail>pass): \($steps | n(. == "fail>pass"))",
      "  failed again       (fail>fail): \($steps | n(. == "fail>fail"))",
      "  left failing at session end:    \($seqs | n(last == "fail"))",
      "what failed (first line of the output, so start a rule'"'"'s message with its name)",
      ($l | map(select(.result == "fail")) | group_by(.first) | sort_by(-length)[:15][] | "  \(length)x \(.[0].first)")
  ' "$log"
  exit 0
}
[ "${1:-}" = stats ] && stats "${2:-}"

input=$(cat)

SKIP=75 # a check returns this when it could not RUN (no container, tool missing). Not a failure: never blocks.

# Every edit. Must be FAST (budget ~5s) and scoped to the one file: lint, types, antipatterns.
on_edit() { # $1 = path of the edited file
  case "$1" in
    # *.php) vendor/bin/pint --test "$1" && vendor/bin/phpstan analyse --no-progress --error-format=raw "$1" ;;
    *) return 0 ;;
  esac
}

# Before every `git commit`. Tests + contracts; slower is fine, the hook timeout is the ceiling.
# ponytail: runs against the working tree, not the staged snapshot. Stash-unstaged if that ever bites.
on_commit() {
  return 0 # e.g. php artisan test --stop-on-failure
}

# Lines this change ADDS to a file ("NNN:text"), so rules judge the delta and leave legacy code alone.
# A file git doesn't know yet counts as all new.
added_lines() { # $1 = file
  if git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    git diff -U0 HEAD -- "$1" | awk '/^@@/{split($3,a,","); n=substr(a[1],2)+0; next} /^\+\+\+/{next} /^\+/{print n ":" substr($0,2); n++}'
  else
    grep -n '' -- "$1"
  fi
}

# ponytail: repo identity = basename of origin's URL, so every worktree of a repo shares one rules file.
repo=$(basename -s .git "$(git remote get-url origin 2>/dev/null)" 2>/dev/null)
rules="${VATS_HOME:-$HOME/.claude/vats}/$repo.sh"
# Log only where there are checks to judge: a rules file (personal mode) or this script living in the repo (team mode).
active=; case "$(cd "$(dirname "$0")" && pwd -P)/" in "$(pwd -P)"/*) active=1 ;; esac
# shellcheck disable=SC1090
[ -f "$rules" ] && ! [ "$rules" -ef "$0" ] && . "$rules" && active=1

now_us() { local t=${EPOCHREALTIME:-0}; echo "${t/[.,]/}"; } # ponytail: needs bash 5; older bash logs ms as 0

record() { # $1 = pass|fail|skip, $2 = ms, $3 = output. Must never break the hook, so every error is swallowed.
  [ -n "$active" ] || return 0
  { mkdir -p "$(dirname "$log")" && jq -cn --arg repo "${repo:-$(basename "$PWD")}" --arg mode "$mode" --arg file "${file:-}" \
      --arg result "$1" --argjson ms "$2" --arg session "$(jq -r '.session_id // ""' <<<"$input")" \
      --arg first "$([ "$1" = fail ] && head -n 1 <<<"$3")" \
      '{ts: now | floor, repo: $repo, mode: $mode, file: $file, result: $result, ms: $ms, session: $session, first: $first}' >>"$log"
  } 2>/dev/null
  return 0
}

run() { # silent on success; on failure hand Claude the tail of the output, not the whole log (context is not free)
  local out rc t0 result=pass
  t0=$(now_us); out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq "$SKIP" ]; then result=skip; elif [ "$rc" -ne 0 ]; then result=fail; fi
  record "$result" "$(( ($(now_us) - t0) / 1000 ))" "$out"
  [ "$result" = fail ] || exit 0
  printf 'vats (%s) failed. Fix this before continuing:\n%s\n' "$mode" "$(printf '%s\n' "$out" | tail -n 40)" >&2
  exit 2
}

mode=${1:-}
case "$mode" in
  edit)
    file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
    [ -n "$file" ] && [ -f "$file" ] || exit 0
    run on_edit "$file"
    ;;
  commit)
    # ponytail: loose match ("git ... commit" inside one command segment). A false positive only costs one extra test run.
    jq -e '.tool_input.command // "" | test("\\bgit\\b[^;&|]*\\bcommit\\b")' <<<"$input" >/dev/null || exit 0
    run on_commit
    ;;
  *)
    echo "usage: vats.sh edit|commit  (hook JSON on stdin)  |  vats.sh stats [days]" >&2
    exit 1
    ;;
esac
