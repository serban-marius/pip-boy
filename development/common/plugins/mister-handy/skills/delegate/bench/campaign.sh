#!/bin/bash
# campaign.sh <parallel> <reps> <arm>...: every task × arm × rep not yet in results.jsonl, <parallel> runs at a time
# Tasks in BENCH_TASKS (space-separated) or tasks/order, smallest first.
set -u
here=$(cd "$(dirname "$0")" && pwd)
par=${1:?usage: campaign.sh <parallel> <reps> <arm>...}; reps=${2:?}; shift 2
results=${BENCH_RESULTS:-$here/results/results.jsonl}
tasks=${BENCH_TASKS:-$(cat "$here/tasks/order")}
touch "$results"
for task in $tasks; do
  for arm in "$@"; do
    for rep in $(seq 1 "$reps"); do
      jq -e --arg t "$task" --arg a "$arm" --argjson r "$rep" 'select(.task == $t and .arm == $a and .rep == $r and (.infra | not) and (.superseded | not))' \
        "$results" >/dev/null 2>&1 || echo "$task $arm $rep"
    done
  done
done | xargs -P "$par" -L 1 bash -c 'bash "$0/run.sh" "$1" "$2" "$3" >/dev/null 2>>"$0/results/campaign.err"; echo "$(date +%H:%M) $1 $2 $3 exit=$?"' "$here"
