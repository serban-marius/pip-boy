#!/usr/bin/env bash

CD_REV="(^|[;&|[:space:]])(cd|pushd)[[:space:]]+[\"']?[$][(][[:space:]]*git([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+rev-parse[[:space:]]+--(absolute-git-dir|git-(common-)?dir|git-path)"

revparse_overseer() {
  local rv='[$][(][[:space:]]*git([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+rev-parse[[:space:]]+--(absolute-git-dir|git-(common-)?dir|git-path)'
  local tail="([^;&|]*/overseer|[[:space:]]+[\"']?overseer)"
  local verb='(^|[;&|[:space:]])(touch|rm|mkdir|rmdir|mv|cp|ln|truncate|tee|find|dd)[[:space:]][^;&|]*'
  local edit='(^|[;&|[:space:]])(sed|perl)[[:space:]][^;&|]*(-[A-Za-z]*i|--in-place)[^;&|]*'
  grep -Eq ">>?[[:space:]]*[\"']?${rv}${tail}|${verb}${rv}${tail}|${edit}${rv}${tail}" <<<"$1"
}
cd_target() {
  local seg=$1 i=1
  local -a w
  seg=$(strip_shell_prefix "$seg")
  read -r -a w <<<"$seg"
  [ "${#w[@]}" -gt 0 ] || return 1
  case "${w[0]}" in cd|pushd) ;; *) return 1 ;; esac
  while [ "$i" -lt "${#w[@]}" ]; do
    case "${w[$i]}" in -P|-L|-e|--) i=$((i + 1)) ;; *) break ;; esac
  done
  [ "$i" -lt "${#w[@]}" ] || return 1
  target_path "${w[$i]}"
}
unresolvable() {
  case "$1" in
    *'$'*|*'`'*|*'~'*) return 0 ;;
  esac
  return 1
}
has_dotgit() { case "$1" in .git|.git/*|*/.git|*/.git/*) return 0 ;; esac; return 1; }
is_inside_git() {
  local a pa g pg
  [ -n "$1" ] || return 1
  a=$(abspath_from "$target_base" "$1")
  pa=$(physical_path "$a")
  for g in "$common" "$gitdir" "$PWD/.git"; do
    pg=$(physical_path "$g")
    case "$pa" in "$pg"|"$pg"/*) return 0 ;; esac
  done
  return 1
}
cd_glob_step() {
  local abs=$1 x
  while IFS= read -r x; do
    is_inside_git "$x" && return 0
    _cd_base=$x
  done < <(expanded_targets "$abs")
  return 1
}
cd_step() {
  local seg=$1 t abs
  grep -Eq "$CD_REV" <<<"$seg" && return 0
  t=$(cd_target "$seg") || return 1
  if [ "${_cd_unknown:-0}" -eq 1 ] && has_dotgit "$t"; then return 0; fi
  if has_glob "$t"; then
    abs=$(abspath_from "$_cd_base" "$t")
    cd_glob_step "$abs"
    return
  fi
  if unresolvable "$t"; then
    has_dotgit "$t" && return 0
    _cd_unknown=1
    return 1
  fi
  abs=$(abspath_from "$_cd_base" "$t")
  is_inside_git "$abs" && return 0
  _cd_base=$abs
  return 1
}
cds_git() {
  local seg
  _cd_base=$target_base
  _cd_unknown=0
  while IFS= read -r seg; do
    cd_step "$seg" && return 0
  done < <(split_segments "$1")
  return 1
}
