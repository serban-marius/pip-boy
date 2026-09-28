#!/usr/bin/env bash

set -u
input=$(cat)
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
command -v jq >/dev/null || { echo "overseer: jq not found, rules are OFF" >&2; exit 1; }
[ -f "$(git rev-parse --git-common-dir)/overseer/off" ] && exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
log="$(git rev-parse --git-dir)/overseer/${branch//\//-}.log"
ASK_PR_LINES=400 # ponytail: size only decides when to ask, never where to cut; a model judge replaces it after pip-boy #25
TESTS='\b(phpunit|pest|artisan test|pytest|vitest|jest|go test|cargo test|(npm|pnpm) (run )?test|yarn test|bun test|rspec|mix test|gradle test|mvn test)\b' # ponytail: fixed list; add a runner when a repo needs one
COMMIT='\bgit\b[^;&|]*\bcommit\b'
PR_CREATE='\bgh\s+pr\s+create\b'

matches() { jq -e --arg re "$1" '.tool_input.command // "" | test($re)' <<<"$input" >/dev/null; }
any() { local f; while read -r f; do "$@" "$f" && return 0; done; return 1; }
block() { printf 'overseer: %s\n' "$*" >&2; exit 2; }
note() { mkdir -p "${log%/*}" && echo "$(date +%s) $1" >>"$log"; }
seen() { [ -f "$log" ] && awk "$1" "$log"; }

is_code() { case "$1" in *.php|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.py|*.go|*.rs|*.rb|*.java|*.kt|*.swift|*.c|*.cc|*.cpp|*.h|*.cs|*.vue|*.svelte) return 0 ;; esac; return 1; }
is_spec() { case "$1" in specs/*|openspec/*) return 0 ;; esac; return 1; }
is_test() { case "/$1" in */tests/*|*/test/*|*/__tests__/*|*/spec/*|*Test.*|*_test.*|*.test.*|*.spec.*|*/test_*.py) return 0 ;; esac; return 1; }
is_commented() { is_code "$1" || case "$1" in *.yaml|*.yml|*.toml|*.sh|*.bash|*Dockerfile|*Makefile) true ;; *) false ;; esac; }
is_code_test() { is_code "$1" && is_test "$1"; }
is_prod() { is_code "$1" && ! is_test "$1" && ! is_spec "$1"; }

default_base() {
  git symbolic-ref -q --short refs/remotes/origin/HEAD && return
  local b; for b in origin/main origin/master main master; do git rev-parse -q --verify "$b" >/dev/null && { echo "$b"; return; }; done
}
branch_files() {
  local b; b=$(default_base)
  [ -n "$b" ] && git diff --name-only "$b"...HEAD 2>/dev/null
  dirty_files
}
has_spec() { branch_files | grep -Eq '^(specs/[^/]+/spec\.md|openspec/changes/[^/]+/)'; }

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
cmd() { jq -r '.tool_input.command // ""' <<<"$input"; }
dirty_files() { git status --porcelain --untracked-files=all | cut -c4-; }

case "${1:-}" in
  session)
    cat "${0%/*}/../rules/overseer.md"
    ;;
  pre-edit)
    f=$(rel_file); [ -n "$f" ] && is_prod "$f" || exit 0
    has_spec || block "no spec in this branch. Write specs/NNN-<slug>/spec.md (or an openspec/changes/<name>/ proposal) before touching $f."
    seen '$2=="test-edit"{t=1} t&&$2=="red"{r=1} END{exit !r}' || # ponytail: once per branch, not per cycle; refactoring on green is legitimate
      block "red first. Write or change a test for this behaviour, run it and watch it fail, then touch $f."
    ;;
  post-edit)
    f=$(rel_file); [ -n "$f" ] || exit 0
    if is_prod "$f"; then note prod-edit; elif is_code_test "$f"; then note test-edit; fi
    [ -f "$f" ] && is_commented "$f" || exit 0
    p=$(prose_comments "$f" | head -n 10)
    [ -z "$p" ] || block "$(printf 'prose comments added to %s. Delete them; the why of a change goes in the PR as a review comment on that line:\n%s' "$f" "$p")"
    ;;
  pre-bash)
    c=$(cmd)
    if matches "$COMMIT"; then
      dirty_files | any is_code || exit 0
      matches "$TESTS" && block "run the tests in their own command, then commit in another; overseer only trusts a run it has seen finish."
      seen '$2~/^(test-edit|prod-edit|red|green)$/{l=$2} END{exit l!="green"}' ||
        block "the last thing that happened was not a green test run. Run the tests, get them green, then commit."
    fi
    if matches "$PR_CREATE"; then
      b=$(grep -oE -- '(--base|-B)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--base|-B)[ =]+//')
      if [ -n "$b" ]; then git rev-parse -q --verify "origin/$b" >/dev/null && b="origin/$b"; else b=$(default_base); fi
      n=0
      while IFS=$'\t' read -r a d f; do is_prod "$f" && [ "$a" != - ] && n=$((n + a + d)); done < <(git diff --numstat "$b"...HEAD 2>/dev/null)
      body=$c; bf=$(grep -oE -- '(--body-file|-F)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--body-file|-F)[ =]+//')
      [ -n "$bf" ] && [ -f "$bf" ] && body+=$(cat "$bf")
      [ "$n" -le "$ASK_PR_LINES" ] || grep -q 'Why not smaller:' <<<"$body" ||
        block "this PR changes $n lines of production code vs $b. If it splits into smaller pieces that each build, pass their tests and can be reviewed on their own, split it into a stack, each PR based on the previous branch. If it cannot, say why in the body: 'Why not smaller: ...'."
      grep -Eq 'specs/|openspec/changes/' <<<"$body" || block "the PR body must link its spec (the specs/... or openspec/changes/... path)."
    fi
    ;;
  post-bash | bash-failed)
    matches "$TESTS" && { [ "$1" = post-bash ] && note green || note red; } # ponytail: any failure is red, even command-not-found; tighten if a fake red ever slips through
    if [ "$1" = post-bash ] && matches "$COMMIT"; then
      files=$(git show --name-only --format= HEAD 2>/dev/null)
      any is_prod <<<"$files" && ! any is_code_test <<<"$files" &&
        block "that commit changes production code but no test. Fine for a pure refactor; otherwise add the test that pins the behaviour."
    fi
    ;;
  *)
    echo "usage: overseer.sh session|pre-edit|post-edit|pre-bash|post-bash|bash-failed  (hook JSON on stdin)" >&2
    exit 1
    ;;
esac
exit 0
