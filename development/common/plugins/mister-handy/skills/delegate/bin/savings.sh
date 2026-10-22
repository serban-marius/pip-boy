#!/usr/bin/env bash
set -u
usage() { echo "usage: savings.sh [--all] [<hq dir>...]" >&2; exit 2; }
all=0
dirs=()
for a in "$@"; do
  case $a in
    --all) all=1 ;;
    -*) usage ;;
    *) a=${a%/}; [ -n "$a" ] || a=/; dirs[${#dirs[@]}]="$a" ;;
  esac
done
[ "$all" -eq 1 ] || [ "${#dirs[@]}" -gt 0 ] || usage
for d in ${dirs[@]+"${dirs[@]}"}; do [ -f "$d/STATUS.md" ] || usage; done
if [ "$all" -eq 1 ]; then
  has() {
    for x in ${dirs[@]+"${dirs[@]}"}; do [ "$x" = "$1" ] && return 0; done
    return 1
  }
  add() {
    [ -f "$1/STATUS.md" ] || return 0
    has "$1" || dirs[${#dirs[@]}]="$1"
  }
  for d in "${HOME:-/nonexistent}/.claude/hq"/*/; do d=${d%/}; add "$d"; done
  for d in "${MISTER_HANDY_WORKSPACES:-${HOME:-/nonexistent}/orca/workspaces}"/*/_hq/; do d=${d%/}; add "$d"; done
fi
files=()
for d in ${dirs[@]+"${dirs[@]}"}; do files[${#files[@]}]="$d/STATUS.md"; done
[ "${#files[@]}" -gt 0 ] || files=(/dev/null)
awk -v base="${MISTER_HANDY_BASELINE_USD:-3.16}" '
BEGIN { printf "%-12s %-24s %-9s %-26s %-7s %8s %9s\n", "hq", "slug", "result", "model", "attempt", "claude", "baseline" }
FNR == 1 {
  d = FILENAME; sub(/\/STATUS\.md$/, "", d)
  n = split(d, p, "/")
  label = (n > 1 ? p[n] : d)
  if (label == "_hq" && n > 1) label = p[n - 1]
}
$3 == "ESCALATE" || ($3 == "DONE" && index($0, "acceptance passed on attempt ")) {
  model = "-"; att = "-"; cost = 0
  if (match($0, /acceptance passed on attempt [0-9]+\/[0-9]+ \([^)]*\)/)) {
    t = substr($0, RSTART + 29, RLENGTH - 29)
    att = t; sub(/ .*/, "", att)
    model = t; sub(/^[^(]*\(/, "", model); sub(/\)$/, "", model)
  }
  if (match($0, /advisor [0-9]+ calls \$[0-9.]+/)) {
    t = substr($0, RSTART, RLENGTH); sub(/.*\$/, "", t); cost = t + 0
  }
  if (match($0, /, claude \$[0-9.]+/)) {
    t = substr($0, RSTART, RLENGTH); sub(/.*\$/, "", t); cost += t + 0
  }
  printf "%-12s %-24s %-9s %-26s %-7s %8s %9s\n", label, $2, $3, model, att, sprintf("$%.2f", cost), sprintf("$%.2f", base)
  claude += cost; total += base
  runner = ""
  if (index(model, "claude:") == 1) runner = "claude"
  else if (index(model, "pi:") == 1 || (model != "-" && model !~ /:/ && index(model, "/"))) runner = "pi"
  if (runner != "") { spend[runner] += cost; bsum[runner] += base }
}
END {
  printf "%-12s %-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "-", "SUBTOTAL pi", "-", "-", "-", sprintf("$%.2f", spend["pi"] + 0), sprintf("$%.2f", bsum["pi"] + 0), bsum["pi"] - spend["pi"]
  printf "%-12s %-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "-", "SUBTOTAL claude", "-", "-", "-", sprintf("$%.2f", spend["claude"] + 0), sprintf("$%.2f", bsum["claude"] + 0), bsum["claude"] - spend["claude"]
  printf "%-12s %-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "-", "TOTAL", "-", "-", "-", sprintf("$%.2f", claude), sprintf("$%.2f", total), total - claude
}
' "${files[@]}"
