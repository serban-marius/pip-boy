#!/bin/bash
# watch.sh <hq dir> [quiet minutes, default 20]
# Blocks until _hq/STATUS.md has something HQ must act on, prints it, exits.
# Exit lines: event lines (ANSWER|BLOCKED|HANDOFF|DONE|DONE-STEP|FAILED|REVISED; HANDOFF-FYI does not wake),
# PR-MERGED|PR-CLOSED <slug> <url>, WAITING-APPROVAL <slug> <last message>, QUIET <min>m <slugs>,
# CHECKPOINT, ALL-SETTLED, ALREADY-WATCHING. Remembers its read offset in <hq>/.watch-offset.

hq=${1:?usage: watch.sh <hq dir> [quiet minutes]}
quiet=$((${2:-20} * 60))
status=$hq/STATUS.md
pidf=$hq/.watch.pid
offf=$hq/.watch-offset
apprf=$hq/.watch-approvals

[ -f "$status" ] || { echo "no $status"; exit 1; }
if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then echo ALREADY-WATCHING; exit 0; fi
echo $$ >"$pidf"
trap 'rm -f "$pidf"' EXIT

lines() { wc -l <"$status" | tr -d ' '; }
n=$(cat "$offf" 2>/dev/null || lines)
quiet_since=$SECONDS
deadline=$((SECONDS + 110 * 60))
next_poll=0
next_ps=0

# slugs dispatched or reopened by HQ and not yet DONE/FAILED/CLOSED; blocked ones listed apart
state() {
  awk '
    $2 == "hq" && ($3 == "DISPATCHED" || $3 == "REOPENED") { live[$4] = 1; last[$4] = "" }
    $2 == "hq" && $3 == "CLOSED" { delete live[$4] }
    $2 != "hq" && ($3 == "DONE" || $3 == "FAILED") { delete live[$2] }
    $2 != "hq" { last[$2] = $3 }
    END { for (s in live) printf "%s%s ", s, (last[s] == "BLOCKED" ? ":blocked" : "") }
  ' "$status"
}

awaiting_merge() {
  awk '
    $2 == "hq" && ($3 == "CLOSED" || $3 == "KEPT" || $3 == "REOPENED") { delete pr[$4] }
    $2 != "hq" && $3 == "DONE" && match($0, /https:\/\/github\.com\/[^ ]+\/pull\/[0-9]+/) { pr[$2] = substr($0, RSTART, RLENGTH) }
    END { for (s in pr) print s, pr[s] }
  ' "$status"
}

ended_prs() {
  local slug url state
  while read -r slug url; do
    state=$(gh pr view "$url" --json state -q .state 2>/dev/null)
    case $state in MERGED | CLOSED) echo "PR-$state $slug $url" ;; esac
  done < <(awaiting_merge)
}

# Orca cards of live slugs (worktrees are siblings of _hq/) on a permission prompt for a minute or more
waiting_approval() {
  command -v orca >/dev/null && command -v jq >/dev/null || return 0
  local live=$1 slug started msg
  touch "$apprf"
  orca worktree ps --limit 1000 --json 2>/dev/null | jq -r --arg ws "$(dirname "$hq")" '
    .result.worktrees[]?
    | (.agents // []) as $a
    | ([$a[] | select(.state == "blocked" or .state == "waiting")] + $a)[0] as $b
    | select(.status == "permission" or any($a[]; .state == "blocked"))
    | select(.path | startswith($ws + "/"))
    | select(now * 1000 - ($b.stateStartedAt // 0) >= 60000)
    | [(.path | ltrimstr($ws + "/")), ($b.stateStartedAt // 0), (($b.lastAssistantMessage // "") | gsub("\\s+"; " ") | .[0:200])]
    | @tsv' >"$apprf.now"
  while IFS=$'\t' read -r slug started msg; do
    tr ' ' '\n' <<<"$live" | sed 's/:blocked$//' | grep -qx -- "$slug" || continue
    grep -qx -- "$slug $started" "$apprf" || echo "WAITING-APPROVAL $slug $msg"
  done <"$apprf.now"
  cut -f1,2 "$apprf.now" | tr '\t' ' ' >"$apprf"
  rm -f "$apprf.now"
}

finish() { echo "$n" >"$offf"; exit 0; }

while :; do
  cur=$(lines)
  if [ "$cur" -gt "$n" ]; then
    events=$(sed -n "$((n + 1)),${cur}p" "$status" | grep -E '^[0-9:]+ [^ ]+ (ANSWER|BLOCKED|HANDOFF|DONE|DONE-STEP|FAILED|REVISED)( |$)')
    n=$cur
    quiet_since=$SECONDS
    [ -n "$events" ] && { printf '%s\n' "$events"; finish; }
  fi
  if [ "$SECONDS" -ge "$next_poll" ]; then
    next_poll=$((SECONDS + 300))
    ended=$(ended_prs)
    [ -n "$ended" ] && { printf '%s\n' "$ended"; finish; }
  fi
  live=$(state)
  if [ "$SECONDS" -ge "$next_ps" ]; then
    next_ps=$((SECONDS + 60))
    waiting=$(waiting_approval "$live")
    [ -n "$waiting" ] && { printf '%s\n' "$waiting"; finish; }
  fi
  [ -z "$live" ] && [ -z "$(awaiting_merge)" ] && { echo ALL-SETTLED; finish; }
  running=$(tr ' ' '\n' <<<"$live" | grep -v ':blocked$' | grep . | tr '\n' ' ')
  if [ -n "$running" ] && [ $((SECONDS - quiet_since)) -ge "$quiet" ]; then
    echo "QUIET $((quiet / 60))m $running"
    finish
  fi
  [ "$SECONDS" -ge "$deadline" ] && { echo CHECKPOINT; finish; }
  sleep 15
done
