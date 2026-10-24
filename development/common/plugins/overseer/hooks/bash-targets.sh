#!/usr/bin/env bash

redir_targets() {
  local m
  while IFS= read -r m; do
    m=$(sed -E 's/^[^<>&]*&?>>?[|]?[[:space:]]*//' <<<"$m")
    [ -n "$m" ] && printf '%s\n' "$(target_path "$m")"
  done < <(grep -oE '(^|[^<>=])>>?[|]?[[:space:]]*[^[:space:]<>|;&]+|(^|[^<>])&>>?[[:space:]]*[^[:space:]<>|;&]+' <<<"$1")
}
tee_targets() {
  local seg a
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    local -a words
    read -r -a words <<<"$seg"
    [ "${#words[@]}" -gt 0 ] || continue
    [ "${words[0]}" = tee ] || continue
    local i=1
    while [ "$i" -lt "${#words[@]}" ]; do
      a=${words[$i]}
      case "$a" in -*) ;; *) printf '%s\n' "$(target_path "$a")" ;; esac
      i=$((i + 1))
    done
  done < <(split_segments "$1")
}
perl_module_opt() { case "$1" in -M*|-m*|-I*|-x*) return 0 ;; esac; return 1; }
inplace_opt() {
  case "$1" in -i|--in-place|-i.*|--in-place=*) return 0 ;; esac
  [[ $1 =~ ^-[A-Za-z]*i ]]
}
script_opt() {
  case "$1" in -e|--expression|-f|--file|--expression=*|--file=*) return 0 ;; esac
  [ "$2" = perl ] && case "$1" in -e|-E|-M|-I) return 0 ;; esac
  [[ $1 =~ ^-[A-Za-z]*[eE]$ ]]
}
opt_value() {
  case "$1" in -e|--expression|-f|--file) return 0 ;; esac
  [ "$2" = perl ] && case "$1" in -e|-E|-M|-I) return 0 ;; esac
  [[ $1 =~ ^-[A-Za-z]*[eE]$ ]]
}
inplace_arg() {
  local a=$1 cmd=$2
  if [ "$cmd" = perl ] && perl_module_opt "$a"; then return; fi
  case "$a" in
    -*)
      inplace_opt "$a" && _ip_inplace=1
      if script_opt "$a" "$cmd"; then
        _ip_have=1
        opt_value "$a" "$cmd" && _ip_skip=1
      fi
      ;;
    *) if [ "$_ip_have" -eq 0 ]; then _ip_have=1; else _ip_files+=("$(target_path "$a")"); fi ;;
  esac
}
inplace_files() {
  local cmd=$1 i=0
  local -a w
  shift
  w=("$@")
  _ip_files=()
  _ip_have=0
  _ip_inplace=0
  while [ "$i" -lt "${#w[@]}" ]; do
    _ip_skip=0
    inplace_arg "${w[$i]}" "$cmd"
    i=$((i + 1 + _ip_skip))
  done
  if [ "$_ip_inplace" -eq 1 ] && [ "${#_ip_files[@]}" -gt 0 ]; then printf '%s\n' "${_ip_files[@]}"; fi
}
inplace_targets() {
  local seg
  local -a w
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    seg=$(strip_redirect_words "$seg")
    read -r -a w <<<"$seg"
    [ "${#w[@]}" -gt 0 ] || continue
    case "${w[0]}" in sed|perl) inplace_files "${w[@]}" ;; esac
  done < <(split_segments "$1")
}
