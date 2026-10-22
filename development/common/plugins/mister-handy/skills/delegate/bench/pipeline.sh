#!/bin/bash
# pipeline.sh <brief> <repo> <status> <prompt>: the pipeline arm. route.sh's pick is recorded, then foreman.sh runs
# its default ladder; an ESCALATE ends the run (scored as escalated; the Claude tier is read from the claude arms).
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
step foreman "exit $?"
