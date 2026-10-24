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
trim_edges() {
  local seg=$1
  while :; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    case "$seg" in
      \(*|\{*) seg=${seg#?} ;;
      *')'|*'}') seg=${seg%?} ;;
      *) break ;;
    esac
  done
  printf '%s' "$seg"
}
drop_timeout() {
  local seg=$1 w
  while :; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    w=${seg%%[[:space:]]*}
    seg=${seg#"$w"}
    case "$w" in -*) continue ;; *) break ;; esac
  done
  printf '%s' "$seg"
}
drop_prefix() {
  local seg=$1 w
  while :; do
    seg=$(trim_edges "$seg")
    w=${seg%%[[:space:]]*}
    case "$w" in
      '') break ;;
      [A-Za-z_]*=*) seg=${seg#"$w"} ;;
      then|do|else|elif|if|while|until|'!'|time|exec|xargs|sudo|command|builtin|env|nohup|nice) seg=${seg#"$w"} ;;
      timeout) seg=$(drop_timeout "${seg#"$w"}") ;;
      *) break ;;
    esac
  done
  printf '%s' "$seg"
}
strip_shell_prefix() { drop_prefix "$1"; }
