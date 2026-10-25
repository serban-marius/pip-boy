#!/usr/bin/env bash

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
post_edit_check() {
  local f=$1 p
  [ -n "$f" ] || return 0
  if is_prod "$f"; then note prod-edit; elif is_code_test "$f"; then note test-edit; fi
  [ -f "$f" ] && is_commented "$f" || return 0
  p=$(prose_comments "$f" | head -n 10)
  [ -z "$p" ] || { note "prose $f"; block post-edit-prose "$(printf 'prose comments added to %s. Delete them; the why of a change goes in the PR as a review comment on that line:\n%s' "$f" "$p")"; }
}
