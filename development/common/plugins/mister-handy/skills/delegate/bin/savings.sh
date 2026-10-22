#!/usr/bin/env bash
set -u
[ $# -ge 1 ] && [ -f "$1/STATUS.md" ] || { echo "usage: savings.sh <hq dir containing STATUS.md>" >&2; exit 2; }
awk -v base="${MISTER_HANDY_BASELINE_USD:-3.16}" '
BEGIN { printf "%-24s %-9s %-26s %-7s %8s %9s\n", "slug", "result", "model", "attempt", "claude", "baseline" }
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
  printf "%-24s %-9s %-26s %-7s %8s %9s\n", $2, $3, model, att, sprintf("$%.2f", cost), sprintf("$%.2f", base)
  claude += cost; total += base
  runner = ""
  if (index(model, "claude:") == 1) runner = "claude"
  else if (index(model, "pi:") == 1 || (model != "-" && model !~ /:/ && index(model, "/"))) runner = "pi"
  if (runner != "") { spend[runner] += cost; bsum[runner] += base }
}
END {
  printf "%-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "SUBTOTAL pi", "-", "-", "-", sprintf("$%.2f", spend["pi"] + 0), sprintf("$%.2f", bsum["pi"] + 0), bsum["pi"] - spend["pi"]
  printf "%-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "SUBTOTAL claude", "-", "-", "-", sprintf("$%.2f", spend["claude"] + 0), sprintf("$%.2f", bsum["claude"] + 0), bsum["claude"] - spend["claude"]
  printf "%-24s %-9s %-26s %-7s %8s %9s saving $%.2f\n", "TOTAL", "-", "-", "-", sprintf("$%.2f", claude), sprintf("$%.2f", total), total - claude
}
' "$1/STATUS.md"
