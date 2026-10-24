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
fire post-edit "$(edit src/Castle.php)"
fire post-bash "$(bash_ 'docker run --rm -v "$PWD":/w -w /w denoland/deno:alpine-2.0.6 deno test --allow-all src/')"
check "deno test is a test runner"              0 pre-bash "$(bash_ 'git add -A && git commit -m castle')"
fire post-edit "$(edit src/Castle.php)"
fire post-bash "$(bash_ 'deno task test')"
check "deno task test is a test runner"         0 pre-bash "$(bash_ 'git add -A && git commit -m castle')"
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
check "Spec impact: None with a reason passes"  0 pre-bash "$(bash_ "gh pr create --title Tooling --body 'Spec impact: None — tooling'")"
check "Spec impact: None without a reason"      2 pre-bash "$(bash_ "gh pr create --title Tooling --body 'Spec impact: None'")" "link its spec"
seq 1 300 | sed 's/^/\/\/ /' >"$R/src/Big.php" && git -C "$R" add -A && git -C "$R" commit -qm big1
seq 1 101 | sed 's/^/\/\/ /' >"$R/src/Big2.php" && git -C "$R" add -A && git -C "$R" commit -qm big2
check "big PR without a reason is blocked"      2 pre-bash "$(bash_ "$PR")" "split-pr-stack"
check "big PR that says why not smaller passes" 0 pre-bash "$(bash_ "gh pr create --title Castle --body 'Spec: specs/001-castle/spec.md. Why not smaller: one migration and its model'")"
check "a stacked PR is trusted on size"         0 pre-bash "$(bash_ "$PR --base feat/castle~2")"
check "--head is measured, not HEAD"            0 pre-bash "$(bash_ "$PR --head feat/castle~2")"

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
check "PR creation reminds to post the why"     2 post-bash "$(bash_ "$PR")" "review comment"
git -C "$R" checkout -q -- src/Legacy.php && rm -f "$R/src/Fresh.php" "$R/NOTES.md"

mkdir -p "$R/src/my dir" && touch "$R/src/my dir/Spaced.php"
check "a path with spaces is still prod code"   0 post-edit "$(edit 'src/my dir/Spaced.php')"
grep -q ' prod-edit$' "$R/.git/overseer/feat-castle.log" || { echo "FAIL spaced path not logged"; fails=$((fails + 1)); }
git -C "$R" add -A && git -C "$R" commit -qm spaced
git -C "$R" worktree add -q "$tmp/wt" -b feat/other
mkdir -p "$R/.git/overseer" && touch "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp/wt R=$tmp/wt check "off in the main repo covers its worktrees" 0 pre-edit "$(R=$tmp/wt edit src/New.php)"
rm "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp/wt R=$tmp/wt check "a worktree keeps its own log (no red yet)" 2 pre-edit "$(R=$tmp/wt edit src/New.php)" "red first"
git -C "$R" worktree add -q "$tmp/wt2" -b feat/agent main
mkdir -p "$tmp/wt2/openspec/changes/agent" && echo '# Agent' >"$tmp/wt2/openspec/changes/agent/proposal.md" && git -C "$tmp/wt2" add -A && git -C "$tmp/wt2" commit -qm spec
git -C "$R" checkout -q main
check "an edit in a worktree reads that worktree's spec" 2 pre-edit "$(R=$tmp/wt2 edit src/Agent.php)" "red first"
fire post-edit "$(R=$tmp/wt2 edit tests/AgentTest.php)"
fire bash-failed "$(jq -nc --arg d "$tmp/wt2" '{cwd:$d,tool_input:{command:"php artisan test"}}')"
check "a red run in a worktree unlocks that worktree" 0 pre-edit "$(R=$tmp/wt2 edit src/Agent.php)"
check "the main checkout keeps its own gate"    2 pre-edit "$(edit src/Agent.php)" "no spec"
git -C "$R" checkout -q feat/castle
git -C "$R" checkout -q --detach
check "detached HEAD is guarded, not crashed"   2 pre-edit "$(edit src/New.php)" "red first"
git -C "$R" checkout -q feat/castle
git -C "$R" checkout -q -b feat/castle-part2
check "a branch inherits its parent's red"      0 pre-edit "$(edit src/New.php)"
git -C "$R" checkout -q -b chore/tooling main
check "no spec, no declaration: blocked"        2 pre-edit "$(edit src/Tool.php)" "no spec"
git -C "$R" commit -q --allow-empty -m "chore: tooling" -m "Spec impact: None — tooling"
check "a Spec impact: None commit stands in"    2 pre-edit "$(edit src/Tool.php)" "red first"
check "no prose removed, no reminder"           0 post-bash "$(bash_ "gh pr create --body 'Spec impact: None — tooling'")"
git -C "$R" checkout -q feat/castle

check "session prints the rules"                0 session '{}'
[ "$(printf '{}' | bash "$S" session)" != "" ] || { echo "FAIL session output is empty"; fails=$((fails + 1)); }
mkdir -p "$R/.git/overseer" && touch "$R/.git/overseer/off"
check "the off switch lets everything through"  0 pre-edit "$(edit src/New.php)"
rm "$R/.git/overseer/off"
CLAUDE_PROJECT_DIR=$tmp check "outside a git repo nothing is guarded" 0 pre-edit '{"tool_input":{"file_path":"/x/src/A.php"}}'
check "unknown event is a usage error"          1 nope '{}'

B=$tmp/bashrepo
export CLAUDE_PROJECT_DIR=$B R=$B
git init -q -b main "$B" && git -C "$B" config user.email t@t && git -C "$B" config user.name t
mkdir -p "$B/src" "$B/tests" && echo '<?php' >"$B/src/Old.php" && git -C "$B" add . && git -C "$B" commit -qm init
git -C "$B" checkout -qb feat/bash

check "touch on the off switch is blocked"      2 pre-bash "$(bash_ 'touch .git/overseer/off')" "state directory"
check "redirect into the off switch is blocked" 2 pre-bash "$(bash_ 'echo 1 > .git/overseer/off')" "state directory"
check "rm of the overseer dir is blocked"       2 pre-bash "$(bash_ 'rm -rf .git/overseer')" "state directory"
check "rm of the git dir is blocked"            2 pre-bash "$(bash_ 'rm -rf .git')" "git directory"
check "mv of the git dir is blocked"            2 pre-bash "$(bash_ 'mv .git /tmp/overseer-gitbak')" "git directory"
check "find -delete on the git dir is blocked"  2 pre-bash "$(bash_ 'find .git -delete')" "git directory"
check "find -delete on the overseer dir is blocked" 2 pre-bash "$(bash_ 'find .git/overseer -delete')" "state directory"
check "dd of= into the off switch is blocked"   2 pre-bash "$(bash_ 'dd of=.git/overseer/off if=/dev/null')" "state directory"
check "&> into the off switch is blocked"       2 pre-bash "$(bash_ 'echo x &> .git/overseer/off')" "state directory"
check "&>> into the off switch is blocked"      2 pre-bash "$(bash_ 'echo x &>> .git/overseer/off')" "state directory"
check "a write after then is blocked"           2 pre-bash "$(bash_ 'if true; then touch .git/overseer/off; fi')" "state directory"
check "a write in a subshell is blocked"        2 pre-bash "$(bash_ '(rm -rf .git/overseer)')" "state directory"
check "tee into the overseer log is blocked"    2 pre-bash "$(bash_ 'echo x | tee -a .git/overseer/feat-bash.log')" "state directory"
check "reading the overseer log is free"        0 pre-bash "$(bash_ 'cat .git/overseer/feat-bash.log')"
check "reading it with stderr redirected is free" 0 pre-bash "$(bash_ 'cat .git/overseer/feat-bash.log 2>/dev/null')"
check "cat > a prod file is blocked"            2 pre-bash "$(bash_ "cat > src/Castle.php <<'X'
<?php class Castle {}
X")" "no spec"
check "tee into a prod file is blocked"         2 pre-bash "$(bash_ 'echo "<?php" | tee src/Castle.php')" "no spec"
check "sed -i on a prod file is blocked"        2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php")" "no spec"
check "sed -i with stderr redirected is blocked" 2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php 2>&1")" "no spec"
check "sed -i with stderr discarded is blocked" 2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php 2>/dev/null")" "no spec"
check "sed -i on two files is blocked"          2 pre-bash "$(bash_ "sed -i 's/php/php /' notes.md src/Old.php")" "no spec"
check "perl -pi with stderr redirected is blocked" 2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' src/Old.php 2>&1")" "no spec"
check "perl -pi on two files is blocked"        2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' notes.md src/Old.php")" "no spec"
check "perl -pi on a prod file is blocked"      2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' src/Old.php")" "no spec"
check "printf > a prod file is blocked"         2 pre-bash "$(bash_ "printf '<?php' > src/Castle.php")" "no spec"
check "reading a prod file is free"             0 pre-bash "$(bash_ 'cat src/Old.php')"
check "writing a prod file outside the repo is free" 0 pre-bash "$(bash_ "cat > /tmp/overseer-tmp.php <<'X'
<?php
X")"
check "grep over prod files is free"            0 pre-bash "$(bash_ 'grep -rn php src')"
check "writing a doc via bash is free"          0 pre-bash "$(bash_ 'echo hi > notes.md')"
check "sed -i on a test file is free"           0 pre-bash "$(bash_ "sed -i 's/a/b/' tests/OldTest.php")"
check "copying a prod file is free"             0 pre-bash "$(bash_ 'cp src/Old.php /tmp/overseer-backup.php')"
check "copying the overseer log out is free"   0 pre-bash "$(bash_ 'cp .git/overseer/feat-bash.log /tmp/overseer-copy.log')"
check "cp -t out of the state is free"          0 pre-bash "$(bash_ 'cp -t /tmp .git/overseer/feat-bash.log')"
check "cp -t into the state is blocked"         2 pre-bash "$(bash_ 'cp -t .git/overseer /tmp/overseer-off')" "state directory"
check "copying into the off switch is blocked"  2 pre-bash "$(bash_ 'cp /tmp/overseer-off .git/overseer/off')" "state directory"
check "moving the overseer log away is blocked" 2 pre-bash "$(bash_ 'mv .git/overseer/feat-bash.log /tmp/overseer-moved.log')" "state directory"
check "git mv is free"                          0 pre-bash "$(bash_ 'git mv src/Old.php src/New.php')"
check "an unrelated -i does not look like sed -i" 0 pre-bash "$(bash_ 'sed -n 1p README.md; grep -i foo src/Old.php')"
check "a heredoc body is not a redirect"        0 pre-bash "$(bash_ "git commit -F - <<'EOF'
moved logic -> src/Old.php
EOF")"
check "a quoted multiline body is not a redirect" 0 pre-bash "$(bash_ "git commit -m 'summary
> src/Old.php'")"
check "a quoted off-switch path is blocked"     2 pre-bash "$(bash_ 'touch ".git/overseer/off"')" "state directory"
check "a quoted redirect into the off switch is blocked" 2 pre-bash "$(bash_ 'echo 1 > ".git/overseer/off"')" "state directory"
check "a quoted prod path is blocked"           2 pre-bash "$(bash_ "cat > \"src/Castle.php\" <<'X'
<?php class Castle {}
X")" "no spec"
check "a quoted tee path is blocked"            2 pre-bash "$(bash_ 'echo "<?php" | tee "src/Castle.php"')" "no spec"
check "the resolved git dir is guarded"         2 pre-bash "$(bash_ 'touch "$(git rev-parse --git-common-dir)/overseer/off"')" "state directory"
check "sed -i on the resolved git dir is blocked" 2 pre-bash "$(bash_ 'sed -i s/a/b/ "$(git rev-parse --git-common-dir)/overseer/x"')" "state directory"
check "a quoted operator is not a redirect"     0 pre-bash "$(bash_ "grep -n '=>' src/Old.php")"
check "a commit message is not a write"         0 pre-bash "$(bash_ 'git commit -m "touch .git/overseer"')"
check "a relative prod target uses the tool cwd" 2 pre-bash "$(jq -nc --arg d "$B/src" --arg c "cat > Castle.php <<'X'
<?php class Castle {}
X" '{cwd:$d,tool_input:{command:$c}}')" "no spec"
check "a relative overseer target uses the tool cwd" 2 pre-bash "$(jq -nc --arg d "$B/.git" --arg c 'touch overseer/off' '{cwd:$d,tool_input:{command:$c}}')" "state directory"
check "cd into .git cannot write the state"    2 pre-bash "$(jq -nc --arg d "$B" --arg c 'cd .git/overseer && touch off' '{cwd:$d,tool_input:{command:$c}}')" "state directory"
check "cd into .git and rm the state is blocked" 2 pre-bash "$(bash_ 'cd .git && rm -rf overseer')" "state directory"
check "cd elsewhere and read is free"           0 pre-bash "$(bash_ 'cd src && cat Old.php')"

ep=$(edit src/Castle.php)
e1=$(printf '%s' "$ep" | bash "$S" pre-edit 2>&1 >/dev/null)
e2=$(printf '%s' "$ep" | bash "$S" pre-edit 2>&1 >/dev/null)
e3=$(printf '%s' "$ep" | bash "$S" pre-edit 2>&1 >/dev/null); c3=$?
if [ -n "$e1" ] && ! grep -qi human <<<"$e1"; then echo "ok   the first edit block is plain"; else echo "FAIL first edit block: $e1"; fails=$((fails + 1)); fi
if [ -n "$e2" ] && ! grep -qi human <<<"$e2"; then echo "ok   the second edit block is still plain"; else echo "FAIL second edit block: $e2"; fails=$((fails + 1)); fi
if [ "$c3" -eq 2 ] && grep -qi human <<<"$e3"; then echo "ok   the third edit block escalates to the human"; else echo "FAIL third edit block (exit $c3): $e3"; fails=$((fails + 1)); fi
L="$B/.git/overseer/feat-bash.log"
grep -q ' block edit-spec$' "$L" && grep -q ' escalate edit-spec$' "$L" && echo "ok   blocks and escalation are logged" || { echo "FAIL block/escalation not logged"; fails=$((fails + 1)); }

printf '%s' "$(edit README.md)" | bash "$S" pre-edit >/dev/null 2>&1
e4=$(printf '%s' "$ep" | bash "$S" pre-edit 2>&1 >/dev/null)
e5=$(printf '%s' "$ep" | bash "$S" pre-edit 2>&1 >/dev/null)
if [ -n "$e4" ] && [ -n "$e5" ] && ! grep -qi human <<<"$e5"; then echo "ok   a pass resets the block streak"; else echo "FAIL streak reset: $e5"; fails=$((fails + 1)); fi

mkdir -p "$B/specs/001-bash" && echo '# Bash' >"$B/specs/001-bash/spec.md"
fire post-edit "$(edit tests/OldTest.php)"
fire bash-failed "$(bash_ 'php artisan test')"
check "sed -i on prod passes after spec and red" 0 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php")"
statrepo=$tmp/statrepo
git init -q -b main "$statrepo" && mkdir -p "$statrepo/.git/overseer"
cat >"$statrepo/.git/overseer/main.log" <<'EOF'
100 block bash-spec
110 pass post-bash
120 pass pre-bash
200 block edit-spec
240 pass pre-edit
300 block bash-green
310 block bash-green
390 pass pre-bash
400 block commit-test
500 pass post-bash
EOF
out=$(cd "$statrepo" && bash "$S" stats </dev/null 2>&1)
if [ "$(grep 'median unblock:' <<<"$out")" = "median unblock: 65s" ]; then echo "ok   stats pairs a streak with its matching pass"
else echo "FAIL stats median: $out"; fails=$((fails + 1)); fi
out=$(cd "$B" && bash "$S" stats </dev/null 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'blocks:' <<<"$out" && grep -q 'bash-overseer' <<<"$out" && grep -qE 'escalations: [1-9][0-9]*' <<<"$out" && grep -qE 'median unblock: ([0-9]+s|-)' <<<"$out"; then echo "ok   stats reports blocks, escalations and unblock time"
else echo "FAIL stats (exit $rc): $out"; fails=$((fails + 1)); fi

git -C "$B" checkout -qb feat/child
printf '%s' "$(edit src/Child.php)" | bash "$S" pre-edit >/dev/null 2>&1
if [ -f "$B/.git/overseer/feat-child.log" ] && ! grep -qE ' (block|escalate|pass) ' "$B/.git/overseer/feat-child.log"; then echo "ok   an inherited log drops block streaks"
else echo "FAIL inherited log kept block state"; fails=$((fails + 1)); fi

check "a worktree log is guarded"               2 pre-bash "$(jq -nc --arg d "$tmp/wt" --arg c "echo 1 >> $tmp/repo/.git/worktrees/wt/overseer/feat-other.log" '{cwd:$d,tool_input:{command:$c}}')" "state directory"
jq -nc --arg d "$tmp/wt" --arg c 'touch .git/overseer/off' '{cwd:$d,tool_input:{command:$c}}' | bash "$S" pre-bash >/dev/null 2>&1
out=$(cd "$tmp/repo" && bash "$S" stats </dev/null 2>&1)
if grep -q 'bash-overseer' <<<"$out"; then echo "ok   stats reads worktree logs too"
else echo "FAIL stats missed the worktree log: $out"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
