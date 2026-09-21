#!/usr/bin/env bash
# Self-check for the vats.sh template: fake hook JSON in, exit codes out. Run: ./vats.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
export CLAUDE_PROJECT_DIR=$tmp

# A copy of the template whose checks fail on *.bad files and on every commit.
sed -e 's|^    \*) return 0 ;;|    *.bad) echo boom; return 1 ;;\n    *) return 0 ;;|' \
    -e 's|^  return 0 # e.g.*|  echo testfail; return 1|' "$here/vats.sh" >"$tmp/vats.sh"
touch "$tmp/x.ok" "$tmp/x.bad"

fails=0
check() { # name, expected exit, mode, json
  local err code
  err=$(printf '%s' "$4" | bash "$tmp/vats.sh" "$3" 2>&1 >/dev/null); code=$?
  if [ "$code" -eq "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $code, wanted $2) $err"; fails=$((fails + 1)); fi
}

check "edit, clean file passes silently"   0 edit   "{\"tool_input\":{\"file_path\":\"$tmp/x.ok\"}}"
check "edit, failing check blocks"         2 edit   "{\"tool_input\":{\"file_path\":\"$tmp/x.bad\"}}"
check "edit, missing file is ignored"      0 edit   "{\"tool_input\":{\"file_path\":\"$tmp/nope\"}}"
check "edit, no file_path is ignored"      0 edit   '{"tool_input":{}}'
check "bash, non-commit command ignored"   0 commit '{"tool_input":{"command":"ls -la && git status"}}'
check "bash, git commit runs the tests"    2 commit '{"tool_input":{"command":"git add . && git commit -m wip"}}'
check "bash, git -C path commit too"       2 commit '{"tool_input":{"command":"git -C sub commit -m wip"}}'
check "bash, commit in another segment no" 0 commit '{"tool_input":{"command":"git status; echo commit"}}'
check "unknown mode is a usage error"      1 nope   '{}'

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
