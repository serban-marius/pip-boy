#!/bin/bash
# watch.sh <hq dir> [quiet minutes, default 20]
# Blocks until _hq/STATUS.md has something HQ must act on, prints it, exits.
# Exit lines: event lines (ANSWER|BLOCKED|DONE|FAILED|REVISED), QUIET <min>m <slugs>, CHECKPOINT,
# ALL-SETTLED, ALREADY-WATCHING. Remembers its read offset in <hq>/.watch-offset.

hq=${1:?usage: watch.sh <hq dir> [quiet minutes]}
quiet=$((${2:-20} * 60))
status=$hq/STATUS.md
pidf=$hq/.watch.pid
offf=$hq/.watch-offset

[ -f "$status" ] || { echo "no $status"; exit 1; }
if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then echo ALREADY-WATCHING; exit 0; fi
echo $$ >"$pidf"
trap 'rm -f "$pidf"' EXIT

lines() { wc -l <"$status" | tr -d ' '; }
n=$(cat "$offf" 2>/dev/null || lines)
quiet_since=$SECONDS
deadline=$((SECONDS + 110 * 60))

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

finish() { echo "$n" >"$offf"; exit 0; }

while :; do
  cur=$(lines)
  if [ "$cur" -gt "$n" ]; then
    events=$(sed -n "$((n + 1)),${cur}p" "$status" | grep -E '^[0-9:]+ [^ ]+ (ANSWER|BLOCKED|DONE|FAILED|REVISED)( |$)')
    n=$cur
    quiet_since=$SECONDS
    [ -n "$events" ] && { printf '%s\n' "$events"; finish; }
  fi
  live=$(state)
  [ -z "$live" ] && { echo ALL-SETTLED; finish; }
  running=$(tr ' ' '\n' <<<"$live" | grep -v ':blocked$' | grep . | tr '\n' ' ')
  if [ -n "$running" ] && [ $((SECONDS - quiet_since)) -ge "$quiet" ]; then
    echo "QUIET $((quiet / 60))m $running"
    finish
  fi
  [ "$SECONDS" -ge "$deadline" ] && { echo CHECKPOINT; finish; }
  sleep 15
done
