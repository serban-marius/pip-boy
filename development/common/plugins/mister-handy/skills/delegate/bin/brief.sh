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

brief_risk() {
  sed -n 's/^Risk:[[:space:]]*\([A-Za-z]*\).*/\1/p' "$1" | head -n 1 | tr 'A-Z' 'a-z'
}

brief_prod() {
  grep -iE '(^|[^[:alnum:]_])(prod|production)([^[:alnum:]_]|$)' "$1" |
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
