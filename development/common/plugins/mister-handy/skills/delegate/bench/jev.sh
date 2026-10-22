#!/bin/bash
# jev.sh <cheap-mvp skills/delegate dir> [task-id...]: route.sh's pick and Jev's raw answer per task -> results/jev.jsonl
# Raw = route.sh with threshold 0 on a copy of the brief without its "production" wording, so Jev is always asked.
set -u
. "$(dirname "$0")/lib.sh"
cheap=$(cd "${1:?usage: jev.sh <cheap-mvp delegate dir> [task-id...]}" && pwd); shift
[ $# -gt 0 ] || set -- $(cat "$bench/tasks/order")
out=$bench/results/jev.jsonl
sha=${BENCH_CHEAP_SHA:-$(git -C "$cheap" rev-parse --short HEAD 2>/dev/null)}
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
for task in "$@"; do
  { cat "$bench/tasks/$task/brief.md"; printf '\n## Rules\n- Commit on the branch; never push.\n'; } >"$tmp/w.md"
  pipeline_brief "$tmp/w.md" "$bench/tasks/$task" >"$tmp/$task.md"
  perl -pe 's/\b(production|prod)\b/shipped/gi' "$tmp/$task.md" >"$tmp/$task.raw.md"
  route=$(bash "$cheap/bin/route.sh" "$tmp/$task.md" 2>/dev/null | tail -n 1)
  raw=$(MISTER_HANDY_ROUTE_THRESHOLD=0 bash "$cheap/bin/route.sh" "$tmp/$task.raw.md" 2>/dev/null | tail -n 1)
  read -r agent model conf reason <<<"$raw"
  case "$agent $model" in foreman\ *) choice=cheap ;; "claude sonnet") choice=mid ;; *) choice=top ;; esac
  [ "$reason" = jev ] || choice=""
  jq -nc --arg task "$task" --arg choice "$choice" --arg conf "${conf:-0}" --arg route "$route" --arg raw "$raw" \
    --arg sha "$sha" --arg ts "$(date -u +%FT%TZ)" \
    '{ts: $ts, task: $task, choice: (if $choice == "" then null else $choice end), confidence: ($conf | tonumber),
      route: $route, raw: $raw, cheap_sha: $sha}' | tee -a "$out"
done
