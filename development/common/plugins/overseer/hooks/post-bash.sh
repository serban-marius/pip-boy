#!/usr/bin/env bash

response_text() {
  jq -r '(.tool_response // "") | if type == "string" then . elif type == "object" then ((.stdout // "") + "\n" + (.stderr // "")) else "" end' <<<"$input" 2>/dev/null
}
test_verdict() {
  local out=$1
  grep -qE 'FAILURES!|ERRORS!|test result: FAILED|^FAIL([[:space:]]|$)|^--- FAIL' <<<"$out" && { echo red; return; }
  grep -qE 'Failures: [1-9]|Errors: [1-9]|[1-9][0-9]* (failed|errors?)|Tests:.*[1-9][0-9]* failed' <<<"$out" && { echo red; return; }
  grep -qE 'OK \(|test result: ok|^ok([[:space:]]|$)|all green|[1-9][0-9]* passed|Tests:.*[1-9][0-9]* passed' <<<"$out" && { echo green; return; }
  echo none
}
exit_masked() {
  local c=$1 m suffix
  m=$(jq -r --arg re "$TESTS" '.tool_input.command // "" | (match($re) // {}).string // ""' <<<"$input" 2>/dev/null)
  [ -n "$m" ] || return 1
  suffix=${c#*"$m"}
  [[ $suffix == *'||'* ]] && return 0
  [[ $suffix == *'|'* ]] && ! [[ $c =~ pipefail ]] && return 0
  [[ $suffix == *';'* || $suffix == *$'\n'* ]] && return 0
  return 1
}
post_bash_check() {
  local c=$1 w files out verdict
  if matches "$TESTS"; then
    if [ "$mode" = bash-failed ]; then
      note red
    else
      out=$(response_text)
      verdict=$(test_verdict "$out")
      case "$verdict" in
        red) note red ;;
        green) note green ;;
        *) if exit_masked "$c"; then printf 'overseer: this test run was not counted: its exit is masked. Run the test bare so its failure or pass shows.\n' >&2; else note green; fi ;;
      esac
    fi
  fi
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
