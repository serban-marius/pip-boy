#!/usr/bin/env bash

size_note() {
  local f=$1 s=$2 msg
  msg=$(printf 'overseer size note for %s (advice, not a gate):\n%s' "$f" "$s")
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
}
post_edit_check() {
  local f=$1 p='' s='' msg lines=''
  [ -n "$f" ] || return 0
  if is_prod "$f"; then note prod-edit; elif is_code_test "$f"; then note test-edit; fi
  [ -f "$f" ] || return 0
  if is_commented "$f"; then
    lines=$(added_lines "$f")
    p=$(prose_comments "$f" "$lines" | head -n 10)
  fi
  s=$(oversized "$f" "$lines" | head -n 10)
  if [ -n "$p" ]; then
    note "prose $f"
    msg=$(printf 'prose comments added to %s. Delete them; the why of a change goes in the PR as a review comment on that line:\n%s' "$f" "$p")
    [ -z "$s" ] || msg=$msg$(printf '\n\nsize note (advice, not a gate):\n%s' "$s")
    block post-edit-prose "$msg"
  fi
  [ -z "$s" ] || size_note "$f" "$s"
}
