#!/usr/bin/env bash
# inbox-clean.sh — mark as done every inbox thread whose snapshot verdict is
# "done", remember it in a state file (the notifications API keeps listing done
# threads; only the UI hides them), and print a JSON summary for the digest:
#   { dryRun, markedTotal, marked: {rule: n}, failed, kept: [...] }
# Usage: inbox-clean.sh [--dry-run]
# State: $INBOX_JANITOR_STATE or ~/.local/state/inbox-janitor/done.json ({threadId: updatedAt})
set -euo pipefail
dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
here="$(cd "$(dirname "$0")" && pwd)"
state="${INBOX_JANITOR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/inbox-janitor/done.json}"
mkdir -p "$(dirname "$state")"; [ -f "$state" ] || echo '{}' > "$state"
snap="$(mktemp)"; trap 'rm -f "$snap"' EXIT
"$here/inbox-snapshot.sh" > "$snap"

failed=0
if [ "$dry" = 0 ]; then
  while IFS=$'\t' read -r id updated; do
    if gh api -X DELETE "notifications/threads/$id" >/dev/null 2>&1; then
      jq --arg id "$id" --arg u "$updated" '.[$id] = $u' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
    else
      failed=$((failed + 1))
    fi
  done < <(jq -r '.[] | select(.verdict == "done") | "\(.threadId)\t\(.updatedAt)"' "$snap")
fi

jq --argjson dry "$dry" --argjson failed "$failed" '{
  dryRun: ($dry == 1),
  markedTotal: (([.[] | select(.verdict == "done")] | length) - $failed),
  marked: ([.[] | select(.verdict == "done")] | group_by(.rule) | map({key: .[0].rule, value: length}) | from_entries),
  failed: $failed,
  kept: [.[] | select(.verdict == "keep") | {reason, rule, repo, number: (.url | split("/") | last), title, author: .pr.author.login, url}]
}' "$snap"
