#!/usr/bin/env bash
# vats: verifiers by cadence. Installed by the pip-boy `vats` skill; the two functions below are yours to edit.
# Wired from .claude/settings.json:  PostToolUse(Edit|Write) -> vats.sh edit   ·   PreToolUse(Bash) -> vats.sh commit
# Contract: exit 0 = silent pass. exit 2 + stderr = on edit, Claude gets the failure as a reminder; on commit, the commit is blocked.

set -u
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
command -v jq >/dev/null || { echo "vats: jq not found, verifiers are OFF" >&2; exit 1; }
input=$(cat)

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

run() { # silent on success; on failure hand Claude the tail of the output, not the whole log (context is not free)
  local out
  if ! out=$("$@" 2>&1); then
    printf 'vats (%s) failed. Fix this before continuing:\n%s\n' "$mode" "$(printf '%s\n' "$out" | tail -n 40)" >&2
    exit 2
  fi
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
    echo "usage: vats.sh edit|commit  (hook JSON on stdin)" >&2
    exit 1
    ;;
esac
