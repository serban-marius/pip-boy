#!/bin/bash
# brief.sh: sourced by route.sh and foreman.sh; reads the fields of an _hq brief.

brief_section() {
  awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on' "$1"
}

brief_without() {
  awk -v h="## $2" '$0 == h { off = 1; next } off && /^## / { off = 0 } !off' "$1"
}

brief_acceptance() {
  brief_section "$1" Acceptance | awk '
    /^[[:space:]]*```/ { next }
    { sub(/^[[:space:]]*[-*][[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
    /^`[^`]+`$/ { $0 = substr($0, 2, length($0) - 2) }
    NF'
}

brief_lint() {
  local n=0 cmd w
  while IFS= read -r cmd; do
    n=$((n + 1))
    w=$(sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/[[:space:]].*//' <<<"$cmd")
    if ! bash -n -c "$cmd" 2>/dev/null || ! grep -qE '^([A-Za-z0-9_./~+-]+|\[\[?|!|\(|\{)$' <<<"$w" ||
      { [ -n "${2:-}" ] && grep -qE '^[A-Za-z0-9_.~+-]+$' <<<"$w" && ! type -t "$w" >/dev/null; }; then
      echo "acceptance line $n is not a runnable command: $cmd"
      return 1
    fi
  done < <(brief_acceptance "$1")
}

brief_scope() {
  sed -n 's/^Scope:[[:space:]]*//p' "$1" | head -n 1
}

brief_risk() {
  sed -n 's/^Risk:[[:space:]]*\([A-Za-z]*\).*/\1/p' "$1" | head -n 1 | tr 'A-Z' 'a-z'
}

brief_prod() {
  case $(sed -n 's/^Prod:[[:space:]]*\([A-Za-z]*\).*/\1/p' "$1" | head -n 1 | tr 'A-Z' 'a-z') in
    yes) echo "Prod: yes"; return ;;
    no) return ;;
  esac
  brief_without "$1" Acceptance |
    grep -iE '(deploy|release|ship|push|migrat|run|apply|write|delete|drop|truncate|update|restart)[a-z]*[^.]{0,40}[[:space:]](to|on|in|against|into)[[:space:]]+(the[[:space:]]+)?(prod|production)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])(prod|production)[ -](db|database|databases|cluster|server|servers|host|hosts|infra|infrastructure|environment|env|data|bucket|account|deploy|deployment)([^[:alnum:]_]|$)|live customer data' |
    grep -viE '(^|[^[:alnum:]_])(no|not|never|without|read-only|nothing)([^[:alnum:]_]|$)' | head -n 1
}

brief_pr() {
  sed -nE 's/^PR:[[:space:]]*(ready|draft)[[:space:]]+([^[:space:]]+).*/\1 \2/p' "$1" | head -n 1
}

brief_title() {
  sed -n '1s/^# *[^:]*: *//p' "$1"
}

ladder() {
  if [ -n "${MISTER_HANDY_LADDER:-}" ]; then tr ',' '\n' <<<"$MISTER_HANDY_LADDER"
  else cat "$(dirname "${BASH_SOURCE[0]}")/../ladder"; fi | awk 'NF && $1 !~ /^#/ { print $1, ($2 ? $2 : 1) }'
}
