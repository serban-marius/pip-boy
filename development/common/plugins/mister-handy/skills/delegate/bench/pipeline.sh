#!/bin/bash
# pipeline.sh <brief> <repo> <status> <prompt>: the pipeline arm. route.sh's pick is recorded, then foreman.sh runs
# its default ladder; an ESCALATE ends the run (scored as escalated; the Claude tier is read from the claude arms).
# claude: rungs add one summed result event (cost, turns, tokens of every claude worker run) for run.sh to score.
set -u
. "$(dirname "$0")/lib.sh"
brief=$1 repo=$2 status=$3
cheap=${BENCH_CHEAP_DIR:?BENCH_CHEAP_DIR: a checkout of the cheap-mvp skills/delegate dir}
task=$(basename "$brief" .md)
hq=$(dirname "$status")
pb=$hq/briefs/$task.pipeline.md
pipeline_brief "$brief" "$bench/tasks/$task" >"$pb"

step() { jq -nc --arg s "$1" --arg d "$2" '{type: "pipeline_step", step: $s, detail: $d, t: (now | floor)}'; }
step route "$(bash "$cheap/bin/route.sh" "$pb" 2>/dev/null | tail -n 1)"
bash "$cheap/bin/foreman.sh" "$task" "$pb" "$hq" "$repo" </dev/null
rc=$?
cat "$hq/logs/$task"/*.claude*.log 2>/dev/null | grep '^{' | jq -sc '[.[] | select(.type == "result")] | select(length > 0) |
  {type: "result", subtype: "foreman_claude_workers", total_cost_usd: (map(.total_cost_usd // 0) | add), num_turns: (map(.num_turns // 0) | add),
   usage: {input_tokens: (map(.usage.input_tokens // 0) | add), output_tokens: (map(.usage.output_tokens // 0) | add),
   cache_read_input_tokens: (map(.usage.cache_read_input_tokens // 0) | add), cache_creation_input_tokens: (map(.usage.cache_creation_input_tokens // 0) | add)}}'
step foreman "exit $rc"
