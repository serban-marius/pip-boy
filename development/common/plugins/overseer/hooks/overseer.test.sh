#!/usr/bin/env bash
set -u
here=$(cd "$(dirname "$0")" && pwd)
S=$here/overseer.sh
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
fails=0

check() {
  local err code
  err=$(printf '%s' "$4" | bash "$S" "$3" 2>&1 >/dev/null); code=$?
  if [ "$code" -eq "$2" ] && { [ -z "${5:-}" ] || grep -q -- "$5" <<<"$err"; }; then echo "ok   $1"
  else echo "FAIL $1 (exit $code, wanted $2) $err"; fails=$((fails + 1)); fi
}
edit() { printf '{"tool_input":{"file_path":"%s"}}' "$R/$1"; }
bash_() { jq -nc --arg c "$1" '{tool_input:{command:$c}}'; }
fire() { printf '%s' "$2" | bash "$S" "$1" >/dev/null 2>&1; }

export CLAUDE_PROJECT_DIR=$tmp/repo R=$tmp/repo
git init -q -b main "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
mkdir -p "$R/src" "$R/tests" && echo '<?php' >"$R/src/Old.php" && git -C "$R" add . && git -C "$R" commit -qm init
git -C "$R" checkout -qb feat/castle

check "docs are always free"                    0 pre-edit "$(edit README.md)"
check "a test file is always free"              0 pre-edit "$(edit tests/CastleTest.php)"
check "prod without a spec is blocked"          2 pre-edit "$(edit src/Castle.php)" "no spec"
check "a file outside the repo is ignored"      0 pre-edit '{"tool_input":{"file_path":"/elsewhere/src/X.php"}}'
mkdir -p "$R/specs/001-castle" && echo '# Castle' >"$R/specs/001-castle/spec.md"

check "spec but no red is blocked"              2 pre-edit "$(edit src/Castle.php)" "red first"
fire bash-failed "$(bash_ 'vendor/bin/phpunit')"
check "red without a test edit is not enough"   2 pre-edit "$(edit src/Castle.php)" "red first"
fire post-edit "$(edit tests/CastleTest.php)"
fire bash-failed "$(bash_ 'vendor/bin/phpunit')"
check "test edit then red unlocks prod"         0 pre-edit "$(edit src/Castle.php)"
fire bash-failed "$(bash_ 'ls nope')"
check "a failing non-test command is not red"   0 pre-edit "$(edit src/Castle.php)"

echo 'class Castle {}' >"$R/src/Castle.php" && echo 'test' >"$R/tests/CastleTest.php"
fire post-edit "$(edit src/Castle.php)"
check "commit after an edit, no green: blocked" 2 pre-bash "$(bash_ 'git add -A && git commit -m castle')" "not a green"
fire post-bash "$(bash_ 'php artisan test')"
check "commit after green passes"               0 pre-bash "$(bash_ 'git add -A && git commit -m castle')"
check "tests chained into the commit: blocked"  2 pre-bash "$(bash_ 'npm test && git commit -m x')" "own command"
check "non-commit commands pass"                0 pre-bash "$(bash_ 'git status; echo commit')"

git -C "$R" add -A && git -C "$R" commit -qm castle
check "commit with prod and test: silent"       0 post-bash "$(bash_ 'git commit -m castle')"
echo 'class Castle { }' >"$R/src/Castle.php" && git -C "$R" commit -qam refactor
check "commit with prod, no test: reminder"     2 post-bash "$(bash_ 'git commit -am refactor')" "no test"
check "docs-only dirty tree commits freely"     0 pre-bash "$(echo x >>"$R/README.md"; bash_ 'git commit -am docs')"

PR="gh pr create --title Castle --body 'Spec: specs/001-castle/spec.md'"
check "small PR with its spec passes"           0 pre-bash "$(bash_ "$PR")"
check "PR without the spec path is blocked"     2 pre-bash "$(bash_ "gh pr create --title Castle --body 'hi'")" "link its spec"
printf 'Spec: openspec/changes/castle/\n' >"$tmp/body.md"
check "--body-file is read"                     0 pre-bash "$(bash_ "gh pr create --title Castle --body-file $tmp/body.md")"
seq 1 300 | sed 's/^/\/\/ /' >"$R/src/Big.php" && git -C "$R" add -A && git -C "$R" commit -qm big1
seq 1 101 | sed 's/^/\/\/ /' >"$R/src/Big2.php" && git -C "$R" add -A && git -C "$R" commit -qm big2
check "big PR without a reason is blocked"      2 pre-bash "$(bash_ "$PR")" "Why not smaller"
check "big PR that says why not smaller passes" 0 pre-bash "$(bash_ "gh pr create --title Castle --body 'Spec: specs/001-castle/spec.md. Why not smaller: one migration and its model'")"
check "--base of a stacked PR is honoured"      0 pre-bash "$(bash_ "$PR --base feat/castle~1")"

printf 'a: 1\n' >"$R/deploy.yaml" && printf '<?php\n// legacy note\nclass Legacy {}\n' >"$R/src/Legacy.php" && git -C "$R" add -A && git -C "$R" commit -qm legacy
printf '# Reverb resolves hosts with its own DNS\nb: 2\n' >>"$R/deploy.yaml"
check "prose comment added to yaml: reminder"   2 post-edit "$(edit deploy.yaml)" "Reverb resolves"
printf '    // because the API is slow\n' >>"$R/src/Legacy.php"
check "prose comment added to php: reminder"    2 post-edit "$(edit src/Legacy.php)" "because the API"
git -C "$R" checkout -q -- deploy.yaml src/Legacy.php
printf 'function x() {}\n' >>"$R/src/Legacy.php"
check "legacy comments are left alone"          0 post-edit "$(edit src/Legacy.php)"
printf '/**\n * @return array{a: int}\n */\n#[Test]\n// phpcs:ignore Generic.Foo\n//\n' >>"$R/src/Legacy.php"
check "annotations and directives are allowed"  0 post-edit "$(edit src/Legacy.php)"
printf '    $n = 400; // ponytail: fixed; an env var if a repo ever needs another number\n' >>"$R/src/Legacy.php"
check "a ponytail: marker is allowed"           0 post-edit "$(edit src/Legacy.php)"
printf '# A heading\n' >"$R/NOTES.md"
check "markdown is free"                        0 post-edit "$(edit NOTES.md)"
printf '/**\n * The page read model.\n */\n' >"$R/src/Fresh.php"
check "a new file with a prose docblock"        2 post-edit "$(edit src/Fresh.php)" "page read model"
git -C "$R" checkout -q -- src/Legacy.php && rm -f "$R/src/Fresh.php" "$R/NOTES.md"

mkdir -p "$R/src/my dir" && touch "$R/src/my dir/Spaced.php"
check "a path with spaces is still prod code"   0 post-edit "$(edit 'src/my dir/Spaced.php')"
grep -q prod-edit "$R/.git/overseer/feat-castle.log" && tail -1 "$R/.git/overseer/feat-castle.log" | grep -q prod-edit || { echo "FAIL spaced path not logged"; fails=$((fails + 1)); }
git -C "$R" add -A && git -C "$R" commit -qm spaced
git -C "$R" worktree add -q "$tmp/wt" -b feat/other
mkdir -p "$R/.git/overseer" && touch "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp/wt R=$tmp/wt check "off in the main repo covers its worktrees" 0 pre-edit "$(R=$tmp/wt edit src/New.php)"
rm "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp/wt R=$tmp/wt check "a worktree keeps its own log (no red yet)" 2 pre-edit "$(R=$tmp/wt edit src/New.php)" "red first"
git -C "$R" checkout -q --detach
check "detached HEAD is guarded, not crashed"   2 pre-edit "$(edit src/New.php)" "red first"
git -C "$R" checkout -q feat/castle

check "session prints the rules"                0 session '{}'
[ "$(printf '{}' | bash "$S" session)" != "" ] || { echo "FAIL session output is empty"; fails=$((fails + 1)); }
mkdir -p "$R/.git/overseer" && touch "$R/.git/overseer/off"
check "the off switch lets everything through"  0 pre-edit "$(edit src/New.php)"
rm "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp check "outside a git repo nothing is guarded" 0 pre-edit '{"tool_input":{"file_path":"/x/src/A.php"}}'
check "unknown event is a usage error"          1 nope '{}'

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
