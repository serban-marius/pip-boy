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
write_re=$(sed -n "s/^WRITE_RE='\(.*\)'$/\1/p" "$S")
re_fail=0
for c in 'git add -A && git status' 'git diff --stat'; do [[ $c =~ $write_re ]] && re_fail=1; done
for c in 'rm x' '/bin/rm x' 'git rev-parse --git-dir' 'echo > y'; do [[ $c =~ $write_re ]] || re_fail=1; done
if [ "$re_fail" -eq 0 ]; then echo "ok   WRITE_RE uses word boundaries"; else echo "FAIL WRITE_RE boundaries"; fails=$((fails + 1)); fi

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
check "another repo's .git is not ours"         0 pre-bash "$(bash_ 'rm -rf /tmp/scaffold/.git')"
check "a subdir clone's .git is not ours"       0 pre-bash "$(bash_ 'rm -rf tpl/.git')"
check "a glob around .git is blocked"           2 pre-bash "$(bash_ 'touch .g?t/overseer/off')" "state directory"
check "a glob into an existing state dir is blocked" 2 pre-bash "$(bash_ 'touch .git/overse*/off')" "state directory"
check "a glob behind a path prefix is blocked"  2 pre-bash "$(jq -nc --arg d "$B" --arg c "touch ../${B##*/}/.g?t/overseer/off" '{cwd:$d,tool_input:{command:$c}}')" "state directory"
check "cd through rev-parse --git-dir is blocked" 2 pre-bash "$(bash_ 'cd "$(git rev-parse --git-dir)" && touch overseer/off')" "state directory"
check "cd through rev-parse --git-common-dir is blocked" 2 pre-bash "$(bash_ 'cd "$(git rev-parse --git-common-dir)" && touch overseer/off')" "state directory"
check "cd through rev-parse --absolute-git-dir is blocked" 2 pre-bash "$(bash_ 'cd "$(git rev-parse --absolute-git-dir)" && touch overseer/off')" "state directory"
check "cd through git -C . rev-parse --git-dir is blocked" 2 pre-bash "$(bash_ 'cd "$(git -C . rev-parse --git-dir)" && touch overseer/off')" "state directory"
check "rev-parse --git-path into the state is blocked" 2 pre-bash "$(bash_ 'touch "$(git rev-parse --git-path overseer/off)"')" "state directory"
check "git -C . rev-parse --git-path into the state is blocked" 2 pre-bash "$(bash_ 'touch "$(git -C . rev-parse --git-path overseer/off)"')" "state directory"
check "the README off-switch command is blocked"  2 pre-bash "$(bash_ 'mkdir -p "$(git rev-parse --git-common-dir)/overseer" && touch "$_/off"')" "state directory"
check "cd into another repo's .git is free"      0 pre-bash "$(bash_ 'cd /tmp/x/.git && echo > y')"
check "cd into this .git then touch the state is blocked" 2 pre-bash "$(bash_ 'cd .git && touch overseer/off')" "state directory"
check "chained cd into this .git is blocked"     2 pre-bash "$(bash_ 'cd src && cd ../.git && touch overseer/off')" "state directory"
check "an unknown cd then this .git is blocked"  2 pre-bash "$(jq -nc --arg d "$B/src" --arg c 'cd "$(git rev-parse --show-toplevel)" && cd .git && touch overseer/off' '{cwd:$d,tool_input:{command:$c}}')" "state directory"
check "an unknown cd to the toplevel then a read is free" 0 pre-bash "$(jq -nc --arg d "$B/src" --arg c 'cd "$(git rev-parse --show-toplevel)" && make > out' '{cwd:$d,tool_input:{command:$c}}')"
check "cd into a bare repo elsewhere is free"   0 pre-bash "$(bash_ 'cd ../other.git && git log > /tmp/x')"
check "mv of the git dir is blocked"            2 pre-bash "$(bash_ 'mv .git /tmp/overseer-gitbak')" "git directory"
check "find -delete on the git dir is blocked"  2 pre-bash "$(bash_ 'find .git -delete')" "git directory"
check "find -delete on the overseer dir is blocked" 2 pre-bash "$(bash_ 'find .git/overseer -delete')" "state directory"
check "dd of= into the off switch is blocked"   2 pre-bash "$(bash_ 'dd of=.git/overseer/off if=/dev/null')" "state directory"
check "a symlink to the state dir is blocked"   2 pre-bash "$(bash_ 'ln -s .git/overseer src/lnk')" "state directory"
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
check "tee inside a command substitution is blocked" 2 pre-bash "$(bash_ 'x=$(echo a | tee src/Castle.php)')" "no spec"
check "grep for tee is a read"                  0 pre-bash "$(bash_ 'grep -n tee src/Old.php')"
check "sed -i on a prod file is blocked"        2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php")" "no spec"
check "sed -i with stderr redirected is blocked" 2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php 2>&1")" "no spec"
check "sed -i with stderr discarded is blocked" 2 pre-bash "$(bash_ "sed -i 's/php/php /' src/Old.php 2>/dev/null")" "no spec"
check "sed -i on two files is blocked"          2 pre-bash "$(bash_ "sed -i 's/php/php /' notes.md src/Old.php")" "no spec"
check "perl -pi with stderr redirected is blocked" 2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' src/Old.php 2>&1")" "no spec"
check "perl -pi on two files is blocked"        2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' notes.md src/Old.php")" "no spec"
check "perl -pi on a prod file is blocked"      2 pre-bash "$(bash_ "perl -pi -e 's/php/php /' src/Old.php")" "no spec"
check "perl -Mstrict -pi is still a write"      2 pre-bash "$(bash_ "perl -Mstrict -pi -e 's/php/php /' src/Old.php")" "no spec"
check "printf > a prod file is blocked"         2 pre-bash "$(bash_ "printf '<?php' > src/Castle.php")" "no spec"
check "noclobber >| into a prod file is blocked" 2 pre-bash "$(bash_ 'echo x >| src/Castle.php')" "no spec"
check "perl -Mstrict read is free"              0 pre-bash "$(bash_ "perl -Mstrict -wnle 'print' src/Old.php")"
check "perl -MList::Util read is free"          0 pre-bash "$(bash_ "perl -MList::Util=sum -ne 'print' src/Old.php")"
check "reading a prod file is free"             0 pre-bash "$(bash_ 'cat src/Old.php')"
check "writing a prod file outside the repo is free" 0 pre-bash "$(bash_ "cat > /tmp/overseer-tmp.php <<'X'
<?php
X")"
check "grep over prod files is free"            0 pre-bash "$(bash_ 'grep -rn php src')"
check "writing a doc via bash is free"          0 pre-bash "$(bash_ 'echo hi > notes.md')"
check "sed -i on a test file is free"           0 pre-bash "$(bash_ "sed -i 's/a/b/' tests/OldTest.php")"
check "copying a prod file is free"             0 pre-bash "$(bash_ 'cp src/Old.php /tmp/overseer-backup.php')"
check "cp into a prod file is blocked"          2 pre-bash "$(bash_ 'cp /tmp/overseer-off src/Castle.php')" "no spec"
check "mv into a prod file is blocked"          2 pre-bash "$(bash_ 'mv /tmp/overseer-off src/Castle.php')" "no spec"
check "mv into a prod directory is free"        0 pre-bash "$(bash_ 'mv /tmp/x.php src/')"
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

git -C "$B" checkout -qb feat/alt
epA=$(edit src/A.php)
printf '%s' "$epA" | bash "$S" pre-edit >/dev/null 2>&1
check "alternating Edit and Bash blocks the same gate" 2 pre-bash "$(bash_ 'echo x > src/A.php')" "no spec"
ealt=$(printf '%s' "$epA" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -qi human <<<"$ealt"; then echo "ok   alternating Edit and Bash escalates on the third block"; else echo "FAIL alternating Edit/Bash escalation: $ealt"; fails=$((fails + 1)); fi
git -C "$B" checkout -q feat/bash

git -C "$B" checkout -qb feat/prose
prose_clean='<?php
class Prose {}'
prose_bad='<?php
// because the API is slow
class Prose {}'
last_prose=''
printf '%s\n' "$prose_bad" >"$B/src/Prose.php"
fire post-edit "$(edit src/Prose.php)"
printf '%s\n' "$prose_clean" >"$B/src/Prose.php"
fire post-edit "$(edit src/Prose.php)"
printf '%s\n' "$prose_bad" >"$B/src/Prose.php"
fire post-edit "$(edit src/Prose.php)"
printf '%s\n' "$prose_bad" >"$B/src/Prose.php"
last_prose=$(printf '%s' "$(edit src/Prose.php)" | bash "$S" post-edit 2>&1 >/dev/null)
if grep -q ' pass post-edit$' "$B/.git/overseer/feat-prose.log" && ! grep -q ' escalate ' "$B/.git/overseer/feat-prose.log" && [ -n "$last_prose" ] && ! grep -qi human <<<"$last_prose"; then echo "ok   a pass of any mode resets the prose block streak"; else echo "FAIL prose block streak reset: $last_prose"; fails=$((fails + 1)); fi
git -C "$B" checkout -q feat/bash
git -C "$B" branch -D feat/prose >/dev/null 2>&1
git -C "$B" branch -D feat/alt >/dev/null 2>&1

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
statrepo2=$tmp/statrepo2
git init -q -b main "$statrepo2" && mkdir -p "$statrepo2/.git/overseer"
cat >"$statrepo2/.git/overseer/main.log" <<'EOF'
100 block edit-spec
200 pass pre-bash
300 block bash-spec
400 pass pre-edit
EOF
out=$(cd "$statrepo2" && bash "$S" stats </dev/null 2>&1)
if [ "$(grep 'median unblock:' <<<"$out")" = "median unblock: 100s" ]; then echo "ok   stats pairs a pre block with either pre pass"
else echo "FAIL stats cross pre-mode median: $out"; fails=$((fails + 1)); fi
out=$(cd "$B" && bash "$S" stats </dev/null 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'blocks:' <<<"$out" && grep -q 'bash-overseer' <<<"$out" && grep -qE 'escalations: [1-9][0-9]*' <<<"$out" && grep -qE 'median unblock: ([0-9]+s|-)' <<<"$out"; then echo "ok   stats reports blocks, escalations and unblock time"
else echo "FAIL stats (exit $rc): $out"; fails=$((fails + 1)); fi

git -C "$B" checkout -qb feat/child
printf '%s' "$(edit src/Child.php)" | bash "$S" pre-edit >/dev/null 2>&1
if [ -f "$B/.git/overseer/feat-child.log" ] && ! grep -qE ' (block|escalate|pass) ' "$B/.git/overseer/feat-child.log"; then echo "ok   an inherited log drops block streaks"
else echo "FAIL inherited log kept block state"; fails=$((fails + 1)); fi

check "a worktree log is guarded"               2 pre-bash "$(jq -nc --arg d "$tmp/wt" --arg c "echo 1 >> $tmp/repo/.git/worktrees/wt/overseer/feat-other.log" '{cwd:$d,tool_input:{command:$c}}')" "state directory"
check "a worktree's .git file is guarded"       2 pre-bash "$(jq -nc --arg d "$tmp/wt" --arg c 'rm -rf .git' '{cwd:$d,tool_input:{command:$c}}')" "git directory"
check "Write to the off switch is blocked"      2 pre-edit "$(jq -nc --arg d "$tmp" --arg f "$R/.git/overseer/off" '{cwd:$d,tool_input:{file_path:$f}}')" "state directory"
jq -nc --arg d "$tmp/wt" --arg c 'touch .git/overseer/off' '{cwd:$d,tool_input:{command:$c}}' | bash "$S" pre-bash >/dev/null 2>&1
out=$(cd "$tmp/repo" && bash "$S" stats </dev/null 2>&1)
if grep -q 'bash-overseer' <<<"$out"; then echo "ok   stats reads worktree logs too"
else echo "FAIL stats missed the worktree log: $out"; fails=$((fails + 1)); fi


T=$tmp/redgate
export CLAUDE_PROJECT_DIR=$T R=$T
git init -q -b main "$T" && git -C "$T" config user.email t@t && git -C "$T" config user.name t
mkdir -p "$T/src" "$T/tests" && echo '<?php' >"$T/src/Old.php" && git -C "$T" add . && git -C "$T" commit -qm init
git -C "$T" checkout -qb feat/gate
mkdir -p "$T/specs/001-gate" && echo '# Gate' >"$T/specs/001-gate/spec.md" && git -C "$T" add . && git -C "$T" commit -qm spec
TL="$T/.git/overseer/feat-gate.log"
resetlog() { mkdir -p "${TL%/*}"; : >"$TL"; }
last_event() { awk '$2=="red"||$2=="green"{l=$2} END{print l}' "$TL" 2>/dev/null; }
expect_event() {
  local got; got=$(last_event)
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (last test event '${got:-none}', wanted '${2:-none}')"; fails=$((fails + 1)); fi
}
resp() { jq -nc --arg c "$1" --arg o "$2" '{tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false,isImage:false}}'; }
resp_str() { jq -nc --arg c "$1" --arg o "$2" '{tool_input:{command:$c},tool_response:$o}'; }

check "python -c writing a prod file is blocked"    2 pre-bash "$(bash_ "python3 -c \"open('src/A.php','w').write('x')\"")" "red first"
check "python heredoc writing a prod file is blocked" 2 pre-bash "$(bash_ "$(printf "python3 - <<'EOF'\nwith open(\"src/A.php\", \"w\") as f:\n    f.write(\"x\")\nEOF")")" "red first"
check "pathlib write_text on a prod file is blocked" 2 pre-bash "$(bash_ "python3 -c \"import pathlib; pathlib.Path('src/A.php').write_text('x')\"")" "red first"
check "python shutil.copy into a prod file is blocked" 2 pre-bash "$(bash_ "python3 -c \"import shutil; shutil.copy('/tmp/x', 'src/A.php')\"")" "red first"
check "python os.rename onto a prod file is blocked" 2 pre-bash "$(bash_ "python3 -c \"import os; os.rename('/tmp/x', 'src/A.php')\"")" "red first"
check "php -r file_put_contents is blocked"         2 pre-bash "$(bash_ "php -r \"file_put_contents('src/A.php', 'x');\"")" "red first"
check "php fopen write is blocked"                  2 pre-bash "$(bash_ "php -r \"fopen('src/A.php', 'w');\"")" "red first"
check "node -e fs.writeFileSync is blocked"         2 pre-bash "$(bash_ "node -e \"require('fs').writeFileSync('src/A.php','x')\"")" "red first"
check "node createWriteStream is blocked"           2 pre-bash "$(bash_ "node -e \"require('fs').createWriteStream('src/A.php')\"")" "red first"
check "node copyFile with a callback is blocked"     2 pre-bash "$(bash_ "node -e \"require('fs').copyFile('/tmp/x','src/A.php',()=>{})\"")" "red first"
check "node fs.rename with a callback is blocked"     2 pre-bash "$(bash_ "node -e \"require('fs').rename('/tmp/x','src/A.php',()=>{})\"")" "red first"
check "a python dict copy is not a file write"        0 pre-bash "$(bash_ "python3 -c \"d={}; e=d.copy()\"")"
check "a pandas rename is not a file write"           0 pre-bash "$(bash_ "python3 -c \"df.rename(columns={'a':'b'})\"")"
check "a node method rename is not a file write"      0 pre-bash "$(bash_ "node -e \"x.rename(y)\"")"
check "copying a prod file out is free"               0 pre-bash "$(bash_ "python3 -c \"import shutil; shutil.copy('src/Old.php','/tmp/x')\"")"
check "ruby -e File.write is blocked"               2 pre-bash "$(bash_ "ruby -e \"File.write('src/A.php','x')\"")" "red first"
check "ruby File.open for write is blocked"         2 pre-bash "$(bash_ "ruby -e \"File.open('src/A.php', 'w')\"")" "red first"
check "ruby FileUtils.cp into prod is blocked"      2 pre-bash "$(bash_ "ruby -e \"require 'fileutils'; FileUtils.cp('/tmp/x', 'src/A.php')\"")" "red first"
check "python writing the off switch is blocked"    2 pre-bash "$(bash_ "python3 -c \"open('.git/overseer/off','w')\"")" "state directory"
check "python reading a prod file is free"          0 pre-bash "$(bash_ "python3 -c \"print(open('src/Old.php').read())\"")"
check "python opening without a write mode is free" 0 pre-bash "$(bash_ "python3 -c \"open('src/Old.php')\"")"
check "python writing outside the repo is free"     0 pre-bash "$(bash_ "python3 -c \"open('/tmp/overseer-accept.txt','w').write('x')\"")"
check "python running a script file is free"        0 pre-bash "$(bash_ "python3 tools/gen.py")"
check "a non-literal python path is blocked"        2 pre-bash "$(bash_ "python3 -c \"open(path, 'w').write('x')\"")" "not a string literal"
check "a non-literal write mode is skipped"         0 pre-bash "$(bash_ "python3 -c \"open('src/Old.php', mode)\"")"
check "a joined python path is not a literal"       2 pre-bash "$(bash_ "python3 -c \"open('a' + 'b', 'w')\"")" "not a string literal"
check "a joined Path receiver is not a literal"     2 pre-bash "$(bash_ "python3 -c \"import pathlib; pathlib.Path('a' + 'b').write_text('x')\"")" "not a string literal"
check "a PHP concatenated path is not a literal"    2 pre-bash "$(bash_ "php -r \"file_put_contents('a'.\$x.'b', 'x');\"")" "not a string literal"
check "python escaped quotes in -c are seen"        2 pre-bash "$(bash_ 'python3 -c "open(\"src/A.php\",\"w\").write(\"x\")"')" "red first"
check "php escaped quotes in -r are seen"           2 pre-bash "$(bash_ 'php -r "file_put_contents(\"src/A.php\", \"x\");"')" "red first"
check "python escaped-quote read is free"           0 pre-bash "$(bash_ 'python3 -c "print(open(\"src/Old.php\").read())"')"
check "perl two-arg open write is blocked"          2 pre-bash "$(bash_ "perl -e 'open(F, \">src/A.php\")'")" "red first"
check "perl three-arg open write is blocked"        2 pre-bash "$(bash_ "perl -e 'open(my \$fh, \">\", \"src/A.php\")'")" "red first"
check "piped python stdin write is blocked"         2 pre-bash "$(bash_ "echo \"open('src/A.php','w').write('x')\" | python3 -")" "red first"
check "python here-string write is blocked"         2 pre-bash "$(bash_ "python3 - <<< \"open('src/A.php','w').write('x')\"")" "red first"
check "php copy into prod is blocked"               2 pre-bash "$(bash_ "php -r \"copy('/tmp/x', 'src/A.php');\"")" "red first"
check "php rename onto prod is blocked"             2 pre-bash "$(bash_ "php -r \"rename('/tmp/x', 'src/A.php');\"")" "red first"
check "node appendFile into prod is blocked"        2 pre-bash "$(bash_ "node -e \"require('fs').appendFile('src/A.php','x',()=>{})\"")" "red first"
check "ruby IO.write into prod is blocked"          2 pre-bash "$(bash_ "ruby -e \"IO.write('src/A.php','x')\"")" "red first"
check "python write_bytes on prod is blocked"       2 pre-bash "$(bash_ "python3 -c \"import pathlib; pathlib.Path('src/A.php').write_bytes(b'x')\"")" "red first"
check "php writing the off switch is blocked"       2 pre-bash "$(bash_ "php -r \"file_put_contents('.git/overseer/off', 'x');\"")" "state directory"
check "node writing the off switch is blocked"      2 pre-bash "$(bash_ "node -e \"require('fs').writeFileSync('.git/overseer/off','x')\"")" "state directory"
check "ruby writing the off switch is blocked"      2 pre-bash "$(bash_ "ruby -e \"File.write('.git/overseer/off','x')\"")" "state directory"

resetlog
fire post-bash "$(resp 'vendor/bin/phpunit 2>&1 | tail -5' "$(printf 'There was 1 failure:\n\nFAILURES!\nTests: 3, Assertions: 3, Failures: 1.')")"
expect_event "phpunit failing behind | tail is red" red
resetlog
fire post-bash "$(resp 'docker run --rm app sh -c "vendor/bin/phpunit --no-coverage tests/XTest.php"; echo exit=$?' "$(printf 'ERRORS!\nTests: 7, Assertions: 0, Errors: 7.\nexit=2')")"
expect_event "phpunit failing behind ; echo is red" red
resetlog
fire post-bash "$(resp 'pytest -q || true' '1 failed, 2 passed in 0.12s')"
expect_event "pytest failing behind || true is red" red
resetlog
fire post-bash "$(resp 'npx jest 2>&1 | tail -3' 'Tests:       1 failed, 2 passed, 3 total')"
expect_event "jest failing behind a pipe is red" red
resetlog
fire post-bash "$(resp 'go test ./...' "$(printf '%s' '--- FAIL: TestX (0.00s)\nFAIL\tpkg\t0.1s')")"
expect_event "go test failure output is red" red
resetlog
fire post-bash "$(resp 'cargo test' 'test result: FAILED. 2 passed; 1 failed')"
expect_event "cargo failure output is red" red
resetlog
fire post-bash "$(resp 'bash hooks/x.test.sh' '5 failed')"
expect_event "this repo's suite failure output is red" red
resetlog
fire post-bash "$(resp 'vendor/bin/phpunit | tail -2' 'Time: 00:00.010, Memory: 6.00 MB')"
expect_event "a masked run with no verdict is not green" ""
err=$(printf '%s' "$(resp 'vendor/bin/phpunit | tail -2' 'Time: 00:00.010, Memory: 6.00 MB')" | bash "$S" post-bash 2>&1 >/dev/null); code=$?
if [ "$code" -eq 0 ] && grep -q 'not counted' <<<"$err" && grep -q 'bare' <<<"$err"; then echo "ok   a masked run with no verdict says it was not counted"; else echo "FAIL masked no-verdict message (exit $code): $err"; fails=$((fails + 1)); fi
out=$(printf '%s' "$(resp 'vendor/bin/phpunit | tail -2' 'Time: 00:00.010, Memory: 6.00 MB')" | bash "$S" post-bash 2>/dev/null)
if grep -q '"additionalContext".*not counted' <<<"$out"; then echo "ok   the masked-run warning reaches the model as context"; else echo "FAIL masked warning context: $out"; fails=$((fails + 1)); fi
resetlog
fire post-bash "$(resp 'set -o pipefail; vendor/bin/phpunit | tail -2' 'Time: 00:00.010, Memory: 6.00 MB')"
expect_event "pipefail with | tail and no verdict is green" green
resetlog
fire post-bash "$(resp 'set -o pipefail; vendor/bin/phpunit | tail -2' 'FAILURES!')"
expect_event "pipefail with | tail and a failure verdict is red" red
resetlog
fire post-bash "$(resp $'vendor/bin/phpunit\necho done' 'Time: 00:00.010, Memory: 6.00 MB')"
expect_event "a newline after the runner is masked and not counted" ""
resetlog
fire post-bash "$(bash_ 'vendor/bin/phpunit')"
expect_event "a bare run with no tool_response is green" green
resetlog
fire post-bash "$(bash_ 'vendor/bin/phpunit | tail -2')"
expect_event "a masked run with no tool_response is not counted" ""
resetlog
fire post-bash "$(resp 'pytest -q' "$(printf '3 passed in 0.12s\n1 failed login attempt')")"
expect_event "unrelated failure words do not turn a pass red" green
resetlog
fire post-bash "$(resp 'vendor/bin/phpunit' '')"
expect_event "a bare run with no output is green" green
resetlog
fire post-bash "$(resp 'vendor/bin/phpunit' 'OK (3 tests, 3 assertions)')"
expect_event "a bare passing run is green" green
resetlog
fire post-bash "$(resp_str 'vendor/bin/phpunit' "$(printf 'FAILURES!\nTests: 2, Failures: 1.')")"
expect_event "a string tool_response is read" red
resetlog
fire bash-failed "$(bash_ 'vendor/bin/phpunit')"
expect_event "bash-failed stays red" red
resetlog
fire bash-failed "$(bash_ 'bash development/common/plugins/overseer/hooks/overseer.test.sh')"
expect_event "bash-failed knows this repo's suite" red

for c in 'vendor/bin/paratest' 'composer unit-tests' 'composer run-script tests' 'composer run unit-tests' 'make unit-tests' 'make feature-tests' 'make tests' 'laravel/core/bin/remotePHP composer unit-tests' 'bash development/common/plugins/overseer/hooks/overseer.test.sh' 'python3 bin/test_jira_preview.py'; do
  resetlog
  fire post-bash "$(resp "$c" "$(printf 'FAILURES!\nTests: 2, Assertions: 2, Failures: 1.')")"
  expect_event "$c with a failure verdict is red" red
done
resetlog
fire post-bash "$(resp 'cat hooks/x.test.sh' 'FAILURES!')"
expect_event "reading a test file is not a test run" ""
resetlog
fire post-bash "$(resp 'git add x.test.sh && git commit -m x' 'FAILURES!')"
expect_event "adding a test file is not a test run" ""
echo '<?php' >>"$T/src/Old.php"
resetlog
fire post-bash "$(resp 'vendor/bin/phpunit' 'OK (1 test)')"
check "a test file path in a commit is not a test run" 0 pre-bash "$(bash_ 'git add x.test.sh && git commit -m x')"
check "paratest chained into a commit still has to run on its own" 2 pre-bash "$(bash_ 'vendor/bin/paratest && git commit -am x')" "own command"

resetlog
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: none' <<<"$msg"; then echo "ok   edit-red with no test run says so"; else echo "FAIL no-event message: $msg"; fails=$((fails + 1)); fi
resetlog
fire post-edit "$(edit tests/XTest.php)"
fire post-bash "$(resp 'vendor/bin/phpunit' 'OK (3 tests, 3 assertions)')"
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: green' <<<"$msg" && grep -qE '[0-9]+ ?(s|sec|min|h)[a-z]* ago' <<<"$msg" && grep -q 'after your test edit' <<<"$msg" && grep -qi 'run the failing test bare' <<<"$msg"; then echo "ok   edit-red after green says what it saw and when"; else echo "FAIL green-event message: $msg"; fails=$((fails + 1)); fi
resetlog
fire post-bash "$(resp 'vendor/bin/phpunit' "$(printf 'FAILURES!\nTests: 1, Failures: 1.')")"
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: red' <<<"$msg" && grep -q 'before any test edit' <<<"$msg"; then echo "ok   edit-red after red says it was before any test edit"; else echo "FAIL red-event message: $msg"; fails=$((fails + 1)); fi
resetlog
printf '%s green\n' "$(($(date +%s) - 150))" >>"$TL"
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: green 2min ago' <<<"$msg"; then echo "ok   the red message reports minutes"; else echo "FAIL minutes age: $msg"; fails=$((fails + 1)); fi
resetlog
printf '%s green\n' "$(($(date +%s) - 7300))" >>"$TL"
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: green 2h ago' <<<"$msg"; then echo "ok   the red message reports hours"; else echo "FAIL hours age: $msg"; fails=$((fails + 1)); fi
resetlog
printf '%s green\n' "$(($(date +%s) - 120))" >>"$TL"
printf '%s test-edit\n' "$(($(date +%s) - 60))" >>"$TL"
msg=$(printf '%s' "$(edit src/A.php)" | bash "$S" pre-edit 2>&1 >/dev/null)
if grep -q 'last test event: green 2min ago' <<<"$msg" && grep -q 'before your last test edit' <<<"$msg"; then echo "ok   a later test edit is named accurately"; else echo "FAIL later test-edit message: $msg"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
