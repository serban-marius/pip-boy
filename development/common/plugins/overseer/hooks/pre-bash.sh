#!/usr/bin/env bash

check_commit() {
  local c=$1
  matches "$COMMIT" || return 0
  dirty_files | any is_code || return 0
  matches "$TESTS" && block bash-tests-own "run the tests in their own command, then commit in another; overseer only trusts a run it has seen finish."
  seen '$2~/^(test-edit|prod-edit|red|green)$/{l=$2} END{exit l!="green"}' ||
    block bash-green "the last thing that happened was not a green test run. Run the tests, get them green, then commit."
}
check_pr() {
  local c=$1 b h n body bf a d f
  matches "$PR_CREATE" || return 0
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
}
check_state() {
  local t x
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      is_overseer_target "$x" && block bash-overseer "do not write to the overseer state directory ($x). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
      is_git_dir_target "$x" && block bash-git-dir "do not write to, remove or move the git directory itself ($x). It holds the branch, the history and the overseer state; change it only through git commands."
    done < <(expanded_targets "$t")
  done <<<"$1"
}
check_writes() {
  local t f
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    f=$(rel_target "$t")
    is_prod "$f" && prod_gate "$f" bash-spec bash-red
  done <<<"$1"
}
write_gate() {
  local c=$1 rh cc wt st state_all
  load_targets
  rh=$(strip_heredocs "$c")
  cc=$(strip_cmd_quotes "$rh")
  revparse_overseer "$rh" && block bash-overseer "do not write to the overseer state directory (resolved through git rev-parse). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  wt=$(write_targets "$cc")
  st=$(state_targets "$cc")
  state_all=$wt
  [ -n "$st" ] && state_all=$(printf '%s\n%s' "$wt" "$st")
  [ -n "$state_all" ] && cds_git "$rh" && block bash-overseer "do not change into .git and then write to the overseer state directory. The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  check_state "$state_all"
  check_writes "$wt"
}
pre_bash_checks() {
  check_commit "$1"
  check_pr "$1"
}
