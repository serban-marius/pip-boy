#!/bin/bash
# report.sh [results.jsonl]: markdown tables computed only from the results file (and results/jev.jsonl when present)
# BENCH_LADDER="arm:tries,...": the escalation ladder to simulate.
set -u
here=$(cd "$(dirname "$0")" && pwd)
results=${1:-$here/results/results.jsonl}
jev=$(dirname "$results")/jev.jsonl
ladder=${BENCH_LADDER:-pi-glm5.3-flash-ne:2,pi-deepseek-v4-flash:1,claude-sonnet:1,claude-opus:1}
jq -rs \
  --argjson order "$(jq -Rsc 'split("\n") | map(select(length > 0))' "$here/tasks/order")" \
  --argjson jev "$( [ -s "$jev" ] && jq -sc . "$jev" || echo '[]')" \
  --argjson ladder "$(jq -nc --arg l "$ladder" '$l | split(",") | map(split(":") | {arm: .[0], tries: ((.[1] // "1") | tonumber)})')" \
  -f "$here/report.jq" "$results"
