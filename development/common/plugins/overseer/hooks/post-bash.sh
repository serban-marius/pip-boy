#!/usr/bin/env bash

response_text() {
  jq -r '(.tool_response // "") | if type == "string" then . elif type == "object" then ((.stdout // "") + "\n" + (.stderr // "")) else "" end' <<<"$input" 2>/dev/null
}
test_verdict() {
  local out=$1
  grep -qE 'FAILURES!|ERRORS!|test result: FAILED|^FAIL([[:space:]]|$)|^--- FAIL' <<<"$out" && { echo red; return; }
  grep -qE 'Failures: [1-9]|Errors: [1-9]|Tests:.*[1-9][0-9]* failed|[1-9][0-9]* (failed|errors?)([[:space:]]*[,.]|[[:space:]]*$)' <<<"$out" && { echo red; return; }
  grep -qE 'OK \(|test result: ok|^ok([[:space:]]|$)|all green|Tests:.*[1-9][0-9]* passed|[1-9][0-9]* passed([[:space:]]+in([[:space:]]|$)|[[:space:]]*[,.]|[[:space:]]*$)' <<<"$out" && { echo green; return; }
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
  local c=$1 w files out verdict msg
  if matches "$TESTS"; then
    if [ "$mode" = bash-failed ]; then
      note red
    else
      out=$(response_text)
      verdict=$(test_verdict "$out")
      case "$verdict" in
        red) note red ;;
        green) note green ;;
        *) if exit_masked "$c"; then
             msg='this test run was not counted: its exit is masked. Run the test bare so its failure or pass shows.'
             printf 'overseer: %s\n' "$msg" >&2
             printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"overseer: %s"}}\n' "$msg"
           else note green; fi ;;
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
