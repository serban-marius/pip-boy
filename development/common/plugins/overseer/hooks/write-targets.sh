#!/usr/bin/env bash

load_verb_args() {
  local j=$1
  local -a w
  shift
  w=("$@")
  while [ "$j" -lt "${#w[@]}" ]; do
    case "${w[$j]}" in
      -t|--target-directory) j=$((j + 1)); _target_dir=$(target_path "${w[$j]:-}") ;;
      --target-directory=*) _target_dir=$(target_path "${w[$j]#*=}") ;;
      -*) ;;
      *) _args+=("$(target_path "${w[$j]}")") ;;
    esac
    j=$((j + 1))
  done
}
read_verb_args() {
  local v=$1 clean=$2 start=-1
  local -a w
  read -r -a w <<<"$clean"
  if [ "${w[0]:-}" = "$v" ]; then start=1
  elif [ "${w[0]:-}" = git ] && [ "${w[1]:-}" = "$v" ]; then start=2
  fi
  [ "$start" -ge 0 ] || return 1
  _target_dir=''
  _args=()
  load_verb_args "$start" "${w[@]}"
}
emit_cp() {
  if [ -n "$_target_dir" ]; then echo "$_target_dir"
  elif [ "${#_args[@]}" -gt 0 ]; then echo "${_args[${#_args[@]}-1]}"
  fi
}
emit_mv() {
  if [ -n "$_target_dir" ]; then
    echo "$_target_dir"
    [ "${#_args[@]}" -gt 0 ] && printf '%s\n' "${_args[@]}"
  else
    [ "${#_args[@]}" -gt 0 ] && echo "${_args[${#_args[@]}-1]}"
    [ "${#_args[@]}" -gt 1 ] && printf '%s\n' "${_args[@]:0:${#_args[@]}-1}"
  fi
}
verb_segment() {
  local clean=$1 v
  for v in touch rm mkdir rmdir mv cp ln truncate; do
    read_verb_args "$v" "$clean" || continue
    case "$v" in
      cp) emit_cp ;;
      mv) emit_mv ;;
      *) [ "${#_args[@]}" -gt 0 ] && printf '%s\n' "${_args[@]}" ;;
    esac
  done
}
find_delete_segment() {
  local clean=$1
  local -a w
  read -r -a w <<<"$clean"
  [ "${#w[@]}" -gt 0 ] || return
  local i=0 k del=0
  [ "${w[$i]:-}" = find ] || return
  for ((k = i + 1; k < ${#w[@]}; k++)); do [ "${w[$k]}" = -delete ] && del=1; done
  [ "$del" -eq 1 ] || return
  k=$((i + 1))
  while [ "$k" -lt "${#w[@]}" ]; do
    case "${w[$k]}" in
      -H|-L|-P) k=$((k + 1)) ;;
      -D|-O) k=$((k + 2)) ;;
      -*) break ;;
      *) printf '%s\n' "$(target_path "${w[$k]}")"; k=$((k + 1)) ;;
    esac
  done
}
dd_segment() {
  local clean=$1
  local -a w
  read -r -a w <<<"$clean"
  [ "${#w[@]}" -gt 0 ] || return
  local i=0 k
  [ "${w[$i]:-}" = dd ] || return
  for ((k = i + 1; k < ${#w[@]}; k++)); do
    case "${w[$k]}" in of=*) printf '%s\n' "$(target_path "${w[$k]#of=}")" ;; esac
  done
}
copy_targets() {
  local seg clean
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    clean=$(strip_redirect_words "$seg")
    case "$clean" in
      cp[[:space:]]*|mv[[:space:]]*) verb_segment "$clean" | head -n 1 ;;
    esac
  done < <(split_segments "$1")
}
write_targets() {
  redir_targets "$1"
  tee_targets "$1"
  inplace_targets "$1"
  copy_targets "$1"
}
state_targets() {
  local seg clean
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    clean=$(strip_redirect_words "$seg")
    verb_segment "$clean"
    find_delete_segment "$clean"
    dd_segment "$clean"
  done < <(split_segments "$1")
}
