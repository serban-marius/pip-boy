#!/usr/bin/env bash

abspath_from() (
  set -f
  local base=$1 p=$2 part
  local -a out=()
  case "$p" in /*) ;; *) p=$base/$p ;; esac
  local IFS=/
  for part in $p; do
    case "$part" in
      ''|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  if [ ${#out[@]} -gt 0 ]; then printf '/%s' "${out[@]}"; else printf '/'; fi
)
abspath() { abspath_from "$PWD" "$1"; }

strip_quotes() { local p=$1; p=${p#[\"\']}; p=${p%[\"\']}; printf '%s' "$p"; }
strip_closers() {
  local p=$1
  while :; do
    case "$p" in
      *')'|*'}') p=${p%?} ;;
      *) break ;;
    esac
  done
  printf '%s' "$p"
}
target_path() { strip_quotes "$(strip_closers "$1")"; }
strip_heredocs() {
  awk '
    {
      line=$0
      if (pending != "") {
        if (line == pending || line ~ ("^[ \t]*" pending "[ \t]*$")) pending=""
        next
      }
      if (match(line, /<<-?[ \t]*[\"\047]?[A-Za-z_][A-Za-z0-9_]*[\"\047]?/)) {
        tok=substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", tok)
        gsub(/[\"\047]/, "", tok)
        pending=tok
      }
      print line
    }
  ' <<<"$1"
}
strip_cmd_quotes() { tr '\n' '\036' <<<"$1" | sed -E "s/'([^' <>|;&]*)'/\1/g; s/\"([^\" <>|;&]*)\"/\1/g; s/'[^']*'/__OVERSEER_ARG__/g; s/\"[^\"]*\"/__OVERSEER_ARG__/g" | tr '\036' '\n'; }
clean_cmd() { local c; c=$(strip_heredocs "$1"); strip_cmd_quotes "$c"; }

redir_targets() {
  local m
  while IFS= read -r m; do
    m=$(sed -E 's/^[^<>&]*&?>>?[|]?[[:space:]]*//' <<<"$m")
    [ -n "$m" ] && printf '%s\n' "$(target_path "$m")"
  done < <(grep -oE '(^|[^<>=])>>?[|]?[[:space:]]*[^[:space:]<>|;&]+|(^|[^<>])&>>?[[:space:]]*[^[:space:]<>|;&]+' <<<"$1")
}
strip_redirect_words() {
  local a out="" skip=0
  local -a words
  local bare='^[0-9]*(>>?[|]?|<<?|>&|<&)$|^&>>?$'
  local attached='^[0-9]*(>>?[|]?|<<?|>&|<&)|^&>>?'
  read -r -a words <<<"$1"
  [ "${#words[@]}" -gt 0 ] || return
  for a in "${words[@]}"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    if [[ $a =~ $bare ]]; then skip=1; continue; fi
    if [[ $a =~ $attached ]]; then continue; fi
    out=${out:+$out }$a
  done
  printf '%s' "$out"
}
split_segments() {
  awk '{
    gsub(/\|\||&&|;|\|/, "\n")
    gsub(/(^|[ \t])&([ \t]|$)/, "\n")
    print
  }' <<<"$1"
}
strip_shell_prefix() {
  local seg=$1 w
  while :; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    case "$seg" in
      \(*|\{*) seg=${seg#?}; continue ;;
    esac
    case "$seg" in
      *')'|*'}') seg=${seg%?}; continue ;;
    esac
    w=${seg%%[[:space:]]*}
    case "$w" in
      '') break ;;
      [A-Za-z_]*=*) seg=${seg#"$w"} ;;
      then|do|else|elif|if|while|until|'!'|time|exec|xargs|sudo|command|builtin|env|nohup|nice) seg=${seg#"$w"} ;;
      timeout)
        seg=${seg#"$w"}
        while :; do
          seg=${seg#"${seg%%[![:space:]]*}"}
          w=${seg%%[[:space:]]*}
          seg=${seg#"$w"}
          case "$w" in -*) continue ;; *) break ;; esac
        done
        ;;
      *) break ;;
    esac
  done
  printf '%s' "$seg"
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
inplace_targets() {
  local seg
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    seg=$(strip_redirect_words "$seg")
    local -a w files
    read -r -a w <<<"$seg"
    [ "${#w[@]}" -gt 0 ] || continue
    local cmd=${w[0]} i=1 a have_script=0 inplace=0
    [ "$cmd" = sed ] || [ "$cmd" = perl ] || continue
    files=()
    while [ "$i" -lt "${#w[@]}" ]; do
      a=${w[$i]}
      if [ "$cmd" = perl ]; then
        case "$a" in
          -M*|-m*|-I*|-x*) i=$((i + 1)); continue ;;
        esac
      fi
      case "$a" in
        -*)
          case "$a" in
            -i|--in-place|-i.*|--in-place=*) inplace=1 ;;
            -*) [[ $a =~ ^-[A-Za-z]*i ]] && inplace=1 ;;
          esac
          if [ "$cmd" = sed ]; then
            case "$a" in
              -e|--expression|-f|--file) have_script=1; i=$((i + 1)) ;;
              --expression=*|--file=*) have_script=1 ;;
              -*) [[ $a =~ ^-[A-Za-z]*[eE]$ ]] && { have_script=1; i=$((i + 1)); } ;;
            esac
          else
            case "$a" in
              -e|-E|-M|-I) have_script=1; i=$((i + 1)) ;;
              -*) [[ $a =~ ^-[A-Za-z]*[eE]$ ]] && { have_script=1; i=$((i + 1)); } ;;
            esac
          fi
          ;;
        *)
          if [ "$have_script" -eq 0 ]; then have_script=1
          else files+=("$(target_path "$a")")
          fi
          ;;
      esac
      i=$((i + 1))
    done
    if [ "$inplace" -eq 1 ] && [ "${#files[@]}" -gt 0 ]; then printf '%s\n' "${files[@]}"; fi
  done < <(split_segments "$1")
}
verb_segment() {
  local clean=$1 v
  for v in touch rm mkdir rmdir mv cp ln truncate; do
    local -a w args
    read -r -a w <<<"$clean"
    local i=0 start=-1 j target_dir=""
    if [ "${w[$i]:-}" = "$v" ]; then start=$((i + 1))
    elif [ "${w[$i]:-}" = git ] && [ "${w[$((i + 1))]:-}" = "$v" ]; then start=$((i + 2))
    fi
    [ "$start" -ge 0 ] || continue
    args=()
    j=$start
    while [ "$j" -lt "${#w[@]}" ]; do
      case "${w[$j]}" in
        -t|--target-directory)
          j=$((j + 1)); target_dir=$(target_path "${w[$j]:-}")
          ;;
        --target-directory=*) target_dir=$(target_path "${w[$j]#*=}") ;;
        -*) ;;
        *) args+=("$(target_path "${w[$j]}")") ;;
      esac
      j=$((j + 1))
    done
    case "$v" in
      cp)
        if [ -n "$target_dir" ]; then echo "$target_dir"
        elif [ "${#args[@]}" -gt 0 ]; then echo "${args[${#args[@]}-1]}"
        fi
        ;;
      mv)
        if [ -n "$target_dir" ]; then
          echo "$target_dir"
          [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
        else
          [ "${#args[@]}" -gt 0 ] && echo "${args[${#args[@]}-1]}"
          [ "${#args[@]}" -gt 1 ] && printf '%s\n' "${args[@]:0:${#args[@]}-1}"
        fi
        ;;
      *)
        [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
        ;;
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
revparse_overseer() {
  grep -Eq '(>>?[[:space:]]*["\047]?[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer|(^|[;&|[:space:]])(touch|rm|mkdir|rmdir|mv|cp|ln|truncate|tee|find|dd)[[:space:]][^;&|]*[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer|(^|[;&|[:space:]])(sed|perl)[[:space:]][^;&|]*(-[A-Za-z]*i|--in-place)[^;&|]*[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer)' <<<"$1"
}
cds_git() {
  local seg
  local rev="(^|[;&|[:space:]])(cd|pushd)[[:space:]]+[\"']?[$][(][[:space:]]*git[[:space:]]+rev-parse[[:space:]]+--git-(common-)?dir"
  local dot="(^|[;&|[:space:]])(cd|pushd)[[:space:]]+[\"']?([^;&|[:space:]\"']*/)?[.]git([/[:space:]\"']|$)"
  while IFS= read -r seg; do
    grep -Eq "$rev" <<<"$seg" && return 0
    grep -Eq "$dot" <<<"$seg" && return 0
  done < <(tr ';|&' '\n' <<<"$1")
  return 1
}
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
