#!/bin/bash
# pipeline.sh <brief> <repo> <status> <prompt>: the pipeline arm. route.sh picks; pi goes through foreman.sh,
# Claude (picked, or after ESCALATE) runs as a worker on the same brief. Prints JSON step lines and Claude's stream.
set -u
. "$(dirname "$0")/lib.sh"
brief=$1 repo=$2 status=$3 prompt=$4
cheap=${BENCH_CHEAP_DIR:?BENCH_CHEAP_DIR: the cheap-mvp skills/delegate dir}
task=$(basename "$brief" .md)
hq=$(dirname "$status")
pb=$hq/briefs/$task.pipeline.md
pipeline_brief "$brief" "$bench/tasks/$task" >"$pb"

step() { jq -nc --arg s "$1" --arg d "$2" '{type: "pipeline_step", step: $s, detail: $d, t: (now | floor)}'; }
claude_worker() {
  step claude "$1"
  claude -p --model "$1" --permission-mode auto --output-format stream-json --verbose "$2"
}

route=$(bash "$cheap/bin/route.sh" "$pb" 2>/dev/null | tail -n 1)
step route "$route"
read -r agent model _ <<<"$route"
if [ "$agent" = pi ]; then
  bash "$cheap/bin/foreman.sh" "$task" "$pb" "$hq" "$repo" </dev/null
  rc=$?
  step foreman "exit $rc"
  [ "$rc" -eq 3 ] && claude_worker opus "$prompt
Cheap workers tried first and ran out of attempts; their summary is $hq/logs/$task/summary.md and their changes are uncommitted in the tree."
else
  claude_worker "${model:-opus}" "$prompt"
fi
exit 0
