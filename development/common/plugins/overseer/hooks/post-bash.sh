#!/usr/bin/env bash

post_bash_check() {
  local c=$1 w files
  matches "$TESTS" && { [ "$mode" = post-bash ] && note green || note red; } # ponytail: any failure is red, even command-not-found; tighten if a fake red ever slips through
  if [ "$mode" = post-bash ] && matches "$PR_CREATE" && [ -f "$log" ]; then
    w=$(awk '$2=="prose"{print $3}' "$log" | sort -u | tr '\n' ' ')
    [ -z "$w" ] || block pr-comments "PR open. Earlier you had to delete prose comments from: $w. Post the why of those changes as review comments on their lines (gh api repos/{owner}/{repo}/pulls/<number>/comments with path, line, side=RIGHT, commit_id)."
  fi
  if [ "$mode" = post-bash ] && matches "$COMMIT"; then
    files=$(git show --name-only --format= HEAD 2>/dev/null)
    any is_prod <<<"$files" && ! any is_code_test <<<"$files" &&
      block commit-test "that commit changes production code but no test. Fine for a pure refactor; otherwise add the test that pins the behaviour."
  fi
}
