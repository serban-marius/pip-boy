#!/usr/bin/env bash

physical_path() {
  local d=$1 rest='' r
  while [ -n "$d" ] && [ ! -d "$d" ]; do rest="/${d##*/}$rest"; d=${d%/*}; done
  r=$(cd "${d:-/}" 2>/dev/null && pwd -P) || r=${d:-/}
  printf '%s%s' "${r%/}" "$rest"
}
has_glob() { case "$1" in *[*?\[]*) return 0 ;; esac; return 1; }
expand_globs() {
  local prefix=$1 rest=$2 part tail m found=0
  [ -n "$rest" ] || { printf '%s\n' "$prefix"; return; }
  part=${rest%%/*}
  if [ "$part" = "$rest" ]; then tail=''; else tail=${rest#*/}; fi
  if has_glob "$part"; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      found=1
      if [ -n "$tail" ]; then expand_globs "$m/" "$tail"; else printf '%s\n' "$m"; fi
    done < <(cd "$target_base" 2>/dev/null && compgen -G "$prefix$part")
    [ "$found" -eq 1 ] || { if [ -n "$tail" ]; then printf '%s\n' "$prefix$part/$tail"; else printf '%s\n' "$prefix$part"; fi; }
  elif [ -n "$tail" ]; then
    expand_globs "$prefix$part/" "$tail"
  else
    printf '%s\n' "$prefix$part"
  fi
}
expanded_targets() {
  local t=$1 root='' rest=$t
  if ! has_glob "$t"; then printf '%s\n' "$t"; return; fi
  case "$t" in /*) root=/; rest=${t#/} ;; esac
  expand_globs "$root" "$rest"
}
is_overseer_target() {
  local a pa pc pg pp
  [ -n "$1" ] || return 1
  case "$1" in
    .git/*[*?\[]*|*/.git/*[*?\[]*) return 0 ;;
  esac
  a=$(abspath_from "$target_base" "$1")
  pa=$(physical_path "$a")
  pc=$(physical_path "$common")
  pg=$(physical_path "$gitdir")
  pp=$(physical_path "$PWD/.git")
  case "$pa" in
    "$pc/overseer"|"$pc/overseer/"*|"$pg/overseer"|"$pg/overseer/"*|"$pp/overseer"|"$pp/overseer/"*|"$pc"/worktrees/*/overseer|"$pc"/worktrees/*/overseer/*) return 0 ;;
  esac
  return 1
}
is_git_dir_target() {
  local a pa pc pg pp
  [ -n "$1" ] || return 1
  case "$1" in .git|.git/) return 0 ;; esac
  a=$(abspath_from "$target_base" "$1")
  pa=$(physical_path "$a")
  pc=$(physical_path "$common")
  pg=$(physical_path "$gitdir")
  pp=$(physical_path "$PWD/.git")
  { [ "$pa" = "$pc" ] || [ "$pa" = "$pg" ] || [ "$pa" = "$pp" ]; } && return 0
  return 1
}
