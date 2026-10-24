#!/usr/bin/env bash

set -u
mode=${1:-}
here=${0%/*}
[ "$here" = "$0" ] && here=.
load_targets() {
  [ -n "${_targets_loaded:-}" ] || {
    . "$here/bash-targets.sh"
    common=$(abspath "$(git rev-parse --git-common-dir)")
    gitdir=$(abspath "$(git rev-parse --git-dir)")
    _targets_loaded=1
  }
}

RULE_MODES='post-edit:^post-edit- pre-edit:^edit- pre-bash:^bash- post-bash:^(commit-|pr-)'
RULE_GATES='spec:^(edit|bash)-spec$ red:^(edit|bash)-red$ overseer:^(edit|bash)-overseer$ git-dir:^(edit|bash)-git-dir$'
WRITE_RE='>|tee|sed|perl|rm|mv|cp|touch|mkdir|rmdir|ln|truncate|dd|find|rev-parse|cd|pushd'
ASK_PR_LINES=400 # ponytail: size only decides when to send a PR to split-pr-stack; the skill judges the cut
NO_SPEC='Spec impact: *None *(—|–|-|:) *[^ ]'
TESTS='\b(phpunit|pest|artisan test|pytest|vitest|jest|go test|cargo test|(npm|pnpm) (run )?test|yarn test|bun test|deno (task )?test|rspec|mix test|gradle test|mvn test)\b' # ponytail: fixed list; add a runner when a repo needs one
COMMIT='\bgit\b[^;&|]*\bcommit\b'
PR_CREATE='\bgh\s+pr\s+create\b'

if [ "$mode" = stats ]; then
  up=$(git rev-parse --show-cdup 2>/dev/null) && cd "./$up" || { echo "overseer: stats must run inside a git repo" >&2; exit 1; }
  load_targets
  . "$here/stats.sh"
  stats "$(abspath "$(git rev-parse --git-common-dir)")"
  exit 0
fi

input=$(cat)
workdir() {
  command -v jq >/dev/null || return
  local f d; f=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)
  [ "${f#/}" = "$f" ] && { jq -r '.cwd // empty' <<<"$input" 2>/dev/null; return; }
  case "$f" in
    */.git/*)
      d=${f%%/.git/*}
      [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return; }
      ;;
  esac
  d=${f%/*}; while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done; echo "${d:-/}"
}
wd=$(workdir)
{ [ -n "$wd" ] && cd "$wd" 2>/dev/null; } || cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
target_base=$(pwd)
up=$(git rev-parse --show-cdup 2>/dev/null) && cd "./$up" || exit 0
command -v jq >/dev/null || { echo "overseer: jq not found, rules are OFF" >&2; exit 1; }
[ -f "$(git rev-parse --git-common-dir)/overseer/off" ] && exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
dir="$(git rev-parse --git-dir)/overseer"
log="$dir/${branch//\//-}.log"

matches() { jq -e --arg re "$1" '.tool_input.command // "" | test($re)' <<<"$input" >/dev/null; }
any() { local f; while read -r f; do "$@" "$f" && return 0; done; return 1; }
note() { mkdir -p "${log%/*}" && echo "$(date +%s) $1" >>"$log"; }
seen() { [ -f "$log" ] && awk "$1" "$log"; }
gate_of() {
  local r=$1 e
  for e in $RULE_GATES; do
    [[ $r =~ ${e#*:} ]] && { echo "${e%%:*}"; return; }
  done
  echo "$r"
}
streak() {
  [ -f "$log" ] || { echo 0; return; }
  local g; g=$(gate_of "$1")
  awk -v g="$g" -v gmap="$RULE_GATES" '
    function gate(r,  n,i,a,p) {
      n=split(gmap,a," ")
      for (i=1;i<=n;i++) { p=index(a[i],":"); if (r ~ substr(a[i],p+1)) return substr(a[i],1,p-1) }
      return r
    }
    $2=="pass" { if ($3=="pre-edit" || $3=="pre-bash") n=0; next }
    $2=="block" { if (gate($3)==g) n++ }
    END { print n+0 }
  ' "$log"
}
block() {
  local rule=$1 n; shift
  n=$(streak "$rule"); n=$((n + 1))
  note "block $rule"
  if [ "$n" -ge 3 ]; then
    [ "$n" -eq 3 ] && note "escalate $rule"
    printf 'overseer: %s\noverseer: %s was blocked %s times in a row. Stop and ask the human before trying again.\n' "$*" "$rule" "$n" >&2
  else
    printf 'overseer: %s\n' "$*" >&2
  fi
  exit 2
}
outstanding() {
  [ -f "$log" ] || return 1
  awk -v m="$1" -v map="$RULE_MODES" '
    function mode(r,  n,i,a,p) {
      n=split(map,a," ")
      for (i=1;i<=n;i++) { p=index(a[i],":"); if (r ~ substr(a[i],p+1)) return substr(a[i],1,p-1) }
      return ""
    }
    $2=="block" && mode($3)==m { p=1 }
    $2=="pass" && $3==m { p=0 }
    END { exit !p }
  ' "$log"
}
pre_outstanding() {
  [ -f "$log" ] || return 1
  awk -v map="$RULE_MODES" '
    function mode(r,  n,i,a,p) {
      n=split(map,a," ")
      for (i=1;i<=n;i++) { p=index(a[i],":"); if (r ~ substr(a[i],p+1)) return substr(a[i],1,p-1) }
      return ""
    }
    $2=="block" && (mode($3)=="pre-edit" || mode($3)=="pre-bash") { p=1 }
    $2=="pass" && ($3=="pre-edit" || $3=="pre-bash") { p=0 }
    END { exit !p }
  ' "$log"
}
ok() {
  case "$mode" in
    pre-edit|pre-bash) pre_outstanding && note "pass $mode" ;;
    *) outstanding "$mode" && note "pass $mode" ;;
  esac
  exit 0
}

is_code() { case "$1" in *.php|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.py|*.go|*.rs|*.rb|*.java|*.kt|*.swift|*.c|*.cc|*.cpp|*.h|*.cs|*.vue|*.svelte) return 0 ;; esac; return 1; }
is_spec() { case "$1" in specs/*|openspec/*) return 0 ;; esac; return 1; }
is_test() { case "/$1" in */tests/*|*/test/*|*/__tests__/*|*/spec/*|*Test.*|*_test.*|*.test.*|*.spec.*|*/test_*.py) return 0 ;; esac; return 1; }
is_commented() { is_code "$1" || case "$1" in *.yaml|*.yml|*.toml|*.sh|*.bash|*Dockerfile|*Makefile) true ;; *) false ;; esac; }
is_code_test() { is_code "$1" && is_test "$1"; }
is_prod() { is_code "$1" && ! is_test "$1" && ! is_spec "$1"; }
rel_target() {
  local a; a=$(abspath_from "$target_base" "$1")
  case "$a" in "$PWD"/*) printf '%s' "${a#"$PWD"/}" ;; esac
}

default_base() {
  git symbolic-ref -q --short refs/remotes/origin/HEAD && return
  local b; for b in origin/main origin/master main master; do git rev-parse -q --verify "$b" >/dev/null && { echo "$b"; return; }; done
}
branch_files() {
  local b; b=$(default_base)
  [ -n "$b" ] && git diff --name-only "$b"...HEAD 2>/dev/null
  dirty_files
}
has_spec() {
  branch_files | grep -Eq '^(specs/[^/]+/spec\.md|openspec/changes/[^/]+/)' && return
  local b; b=$(default_base)
  [ -n "$b" ] && git log --format=%B "$b"..HEAD 2>/dev/null | grep -Eq "$NO_SPEC"
}
inherit() {
  [ -f "$log" ] || [ "$branch" = HEAD ] || [ ! -d "$dir" ] && return
  local b n best='' min=''
  while read -r b; do
    [ "$b" != "$branch" ] && [ -f "$dir/${b//\//-}.log" ] && git merge-base --is-ancestor "$b" HEAD 2>/dev/null || continue
    n=$(git rev-list --count "$b"..HEAD)
    [ -z "$min" ] || [ "$n" -lt "$min" ] && { min=$n; best=$b; }
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)
  [ -z "$best" ] || awk '$2!="block" && $2!="escalate" && $2!="pass"' "$dir/${best//\//-}.log" >"$log"
}

rel_file() {
  local f; f=$(jq -r '.tool_input.file_path // empty' <<<"$input")
  case "$f" in "$PWD"/*) echo "${f#"$PWD"/}" ;; /*) ;; *) echo "$f" ;; esac
}
added_lines() {
  if git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    git diff -U0 HEAD -- "$1" | awk '/^@@/{split($3,a,","); n=substr(a[1],2)+0; next} /^\+\+\+/{next} /^\+/{print n ":" substr($0,2); n++}'
  else
    grep -n '' -- "$1"
  fi
}
prose_comments() {
  added_lines "$1" |
    grep -E '^[0-9]+:[[:space:]]*(//|#|/\*|\*|\{\{--|<!--)' |
    grep -vE '^[0-9]+:[[:space:]]*(#!|#\[|(//|#|/\*+|\*/?|\{\{--|<!--|-->|--\}\})[[:space:]]*$)' |
    grep -vE '@[A-Za-z]|phpcs:|phpstan-|psalm-|eslint-|prettier-ignore|@ts-|noqa|type: ?ignore|pylint:|nolint|NOSONAR|//go:|(end)?region|istanbul|c8 ignore|-\*-|shellcheck|yamllint|ponytail:'
}
prod_gate() {
  local f=$1 spec_rule=$2 red_rule=$3
  has_spec || block "$spec_rule" "no spec in this branch. Write specs/NNN-<slug>/spec.md (or an openspec/changes/<name>/ proposal) before touching $f."
  seen '$2=="test-edit"{t=1} t&&$2=="red"{r=1} END{exit !r}' || # ponytail: once per branch, not per cycle; refactoring on green is legitimate
    block "$red_rule" "red first. Write or change a test for this behaviour, run it and watch it fail, then touch $f."
}
write_gate() {
  local c=$1 rh cc state_all wt st t x f
  load_targets
  rh=$(strip_heredocs "$c")
  cc=$(strip_cmd_quotes "$rh")
  revparse_overseer "$rh" && block bash-overseer "do not write to the overseer state directory (resolved through git rev-parse). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  wt=$(write_targets "$cc")
  st=$(state_targets "$cc")
  state_all=$wt
  [ -n "$st" ] && state_all=$(printf '%s\n%s' "$wt" "$st")
  [ -n "$state_all" ] && cds_git "$rh" && block bash-overseer "do not change into .git and then write to the overseer state directory. The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      is_overseer_target "$x" && block bash-overseer "do not write to the overseer state directory ($x). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
      is_git_dir_target "$x" && block bash-git-dir "do not write to, remove or move the git directory itself ($x). It holds the branch, the history and the overseer state; change it only through git commands."
    done < <(expanded_targets "$t")
  done <<<"$state_all"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    f=$(rel_target "$t")
    is_prod "$f" && prod_gate "$f" bash-spec bash-red
  done <<<"$wt"
}
cmd() { jq -r '.tool_input.command // ""' <<<"$input"; }
dirty_files() { git status --porcelain --untracked-files=all | cut -c4-; }

inherit
case "$mode" in
  session)
    cat "${0%/*}/../rules/overseer.md"
    ;;
  pre-edit)
    raw=$(jq -r '.tool_input.file_path // empty' <<<"$input")
    [ -n "$raw" ] || ok
    case "/$raw/" in
      */.git/*|*/.git/)
        load_targets
        is_overseer_target "$raw" && block edit-overseer "do not write to the overseer state directory ($raw). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
        is_git_dir_target "$raw" && block edit-git-dir "do not write to, remove or move the git directory itself ($raw). It holds the branch, the history and the overseer state; change it only through git commands."
        ;;
    esac
    f=$(rel_file); [ -n "$f" ] && is_prod "$f" || ok
    prod_gate "$f" edit-spec edit-red
    ;;
  post-edit)
    f=$(rel_file); [ -n "$f" ] || ok
    if is_prod "$f"; then note prod-edit; elif is_code_test "$f"; then note test-edit; fi
    [ -f "$f" ] && is_commented "$f" || ok
    p=$(prose_comments "$f" | head -n 10)
    [ -z "$p" ] || { note "prose $f"; block post-edit-prose "$(printf 'prose comments added to %s. Delete them; the why of a change goes in the PR as a review comment on that line:\n%s' "$f" "$p")"; }
    ;;
  pre-bash)
    c=$(cmd)
    if [[ $c =~ $WRITE_RE ]]; then write_gate "$c"; fi
    if matches "$COMMIT"; then
      dirty_files | any is_code || ok
      matches "$TESTS" && block bash-tests-own "run the tests in their own command, then commit in another; overseer only trusts a run it has seen finish."
      seen '$2~/^(test-edit|prod-edit|red|green)$/{l=$2} END{exit l!="green"}' ||
        block bash-green "the last thing that happened was not a green test run. Run the tests, get them green, then commit."
    fi
    if matches "$PR_CREATE"; then
      b=$(grep -oE -- '(--base|-B)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--base|-B)[ =]+//')
      if [ -n "$b" ]; then git rev-parse -q --verify "origin/$b" >/dev/null && b="origin/$b"; else b=$(default_base); fi
      h=$(grep -oE -- '(--head|-H)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--head|-H)[ =]+//')
      [ -n "$h" ] || h=HEAD
      n=0
      [ "$b" = "$(default_base)" ] && while IFS=$'\t' read -r a d f; do is_prod "$f" && [ "$a" != - ] && n=$((n + a + d)); done < <(git diff --numstat "$b...$h" 2>/dev/null)
      body=$c; bf=$(grep -oE -- '(--body-file|-F)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--body-file|-F)[ =]+//')
      [ -n "$bf" ] && [ -f "$bf" ] && body+=$(cat "$bf")
      [ "$n" -le "$ASK_PR_LINES" ] || grep -q 'Why not smaller:' <<<"$body" ||
        block bash-pr-size "this PR changes $n lines of production code vs $b. Cut it into a stack by function with the split-pr-stack skill (caravan): each PR builds, passes its tests and can be reviewed on its own. If it cannot be smaller, say why in the body: 'Why not smaller: ...'."
      grep -Eq "specs/|openspec/changes/|$NO_SPEC" <<<"$body" || block bash-pr-spec "the PR body must link its spec (the specs/... or openspec/changes/... path), or say 'Spec impact: None — <why>'."
    fi
    ;;
  post-bash | bash-failed)
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
    ;;
  *)
    echo "usage: overseer.sh session|pre-edit|post-edit|pre-bash|post-bash|bash-failed|stats  (hook JSON on stdin)" >&2
    exit 1
    ;;
esac
ok
