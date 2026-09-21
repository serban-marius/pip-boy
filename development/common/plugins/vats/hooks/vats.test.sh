#!/usr/bin/env bash
# Self-check for the vats.sh template: fake hook JSON in, exit codes out. Run: ./vats.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # name, expected exit, script, mode, json, [text stderr must contain]
  local err code
  err=$(printf '%s' "$5" | bash "$3" "$4" 2>&1 >/dev/null); code=$?
  if [ "$code" -eq "$2" ] && { [ -z "${6:-}" ] || grep -q -- "$6" <<<"$err"; }; then echo "ok   $1"
  else echo "FAIL $1 (exit $code, wanted $2) $err"; fails=$((fails + 1)); fi
}
edit() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }

# ── team mode: the script lives in the repo, with checks that fail on *.bad files and on every commit ──
export CLAUDE_PROJECT_DIR=$tmp/team && mkdir -p "$CLAUDE_PROJECT_DIR"
T=$CLAUDE_PROJECT_DIR/vats.sh
sed -e 's|^    \*) return 0 ;;|    *.bad) echo boom; return 1 ;;\n    *) return 0 ;;|' \
    -e 's|^  return 0 # e.g.*|  echo testfail; return 1|' "$here/vats.sh" >"$T"
touch "$tmp/team/x.ok" "$tmp/team/x.bad"

check "edit, clean file passes silently"   0 "$T" edit   "$(edit "$tmp/team/x.ok")"
check "edit, failing check reaches Claude" 2 "$T" edit   "$(edit "$tmp/team/x.bad")" boom
check "edit, missing file is ignored"      0 "$T" edit   "$(edit "$tmp/team/nope")"
check "edit, no file_path is ignored"      0 "$T" edit   '{"tool_input":{}}'
check "bash, non-commit command ignored"   0 "$T" commit '{"tool_input":{"command":"ls -la && git status"}}'
check "bash, git commit runs the tests"    2 "$T" commit '{"tool_input":{"command":"git add . && git commit -m wip"}}' testfail
check "bash, git -C path commit too"       2 "$T" commit '{"tool_input":{"command":"git -C sub commit -m wip"}}'
check "bash, commit in another segment no" 0 "$T" commit '{"tool_input":{"command":"git status; echo commit"}}'
check "unknown mode is a usage error"      1 "$T" nope   '{}'

# ── personal mode: the pristine shipped script + a rules file named after the repo's origin ──
# The script runs from wherever the plugin is cached; the rules come from $VATS_HOME (default ~/.claude/vats).
P=$here/vats.sh && export VATS_HOME=$tmp/home && mkdir -p "$VATS_HOME"
cat >"$VATS_HOME/demo.sh" <<'EOF'
on_edit()   { added_lines "$1" | grep -E '^[0-9]+:.*FORBIDDEN' && return 1; return 0; }
on_commit() { return "$SKIP"; }
EOF
repo() { # dir, origin url
  git init -q "$1" && git -C "$1" remote add origin "$2" && git -C "$1" config user.email t@t && git -C "$1" config user.name t
}
export CLAUDE_PROJECT_DIR=$tmp/demo && repo "$CLAUDE_PROJECT_DIR" git@example.com:org/demo.git
printf 'legacy FORBIDDEN line\n' >"$tmp/demo/old.php" && git -C "$tmp/demo" add . && git -C "$tmp/demo" commit -qm init

printf 'a clean new line\n' >>"$tmp/demo/old.php"
check "delta: legacy violations are left alone" 0 "$P" edit "$(edit "$tmp/demo/old.php")"
printf 'a new FORBIDDEN line\n' >>"$tmp/demo/old.php"
check "delta: an added violation is reported"   2 "$P" edit "$(edit "$tmp/demo/old.php")" "3:a new FORBIDDEN"
printf 'FORBIDDEN\n' >"$tmp/demo/new.php"
check "delta: a brand-new file counts whole"    2 "$P" edit "$(edit "$tmp/demo/new.php")" "1:FORBIDDEN"
check "skip: a check that can't run never blocks" 0 "$P" commit '{"tool_input":{"command":"git commit -m x"}}'

export CLAUDE_PROJECT_DIR=$tmp/other && repo "$CLAUDE_PROJECT_DIR" git@example.com:org/other.git
printf 'FORBIDDEN\n' >"$tmp/other/new.php"
check "a repo without a rules file is left alone" 0 "$P" edit "$(edit "$tmp/other/new.php")"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
