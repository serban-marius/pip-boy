#!/bin/bash
# nan-usage: estimated NAN credits left, from /v1/usage tokens × measured credits per 1M tokens.
#   nan-usage                 status; exit 2 when credits left < NAN_WARN_PCT (20) % of the period
#   nan-usage --quiet         one line, for scripts / status lines
#   nan-usage set <left>      anchor to the dashboard's "Credits left this period" (do it now and then)
# NAN has no balance endpoint: the anchor + per-model token deltas keep the estimate within a few %.
#
# Env: NAN_API_KEY       key to use; default the nan apiKey in ~/.pi/agent/models.json (a literal,
#                        $ENV_VAR or !command, resolved the way pi does it)
#      NAN_USAGE_FILE    read this file as the /v1/usage answer instead of calling NAN (offline/tests)
#      NAN_CREDITS_STATE state file; default ${XDG_CONFIG_HOME:-~/.config}/mister-handy/nan-credits.json
#      NAN_PERIOD_CREDITS  credits in a full period (7000); NAN_WARN_PCT  warning threshold (20)
set -u
state=${NAN_CREDITS_STATE:-${XDG_CONFIG_HOME:-$HOME/.config}/mister-handy/nan-credits.json}
period=${NAN_PERIOD_CREDITS:-7000}
warn=${NAN_WARN_PCT:-20}

# credits per 1M total tokens (input+cached+output), measured on agentic coding runs 2026-11-11;
# models not measured use NAN's "typical" figure, unknown ones a conservative 25.
rates='{"deepseek-v4-flash":1.05,"deepseek-v4-pro":8.54,"glm5.3":13.26,"glm5.3-flash":2.01,"hy4":6.57,
"kimi-k3.1-pro":34.66,"mimo-v2.6-flash":1.08,"qwen3.8-flash":1.28,"qwen3.8-max":25.65,"qwen3.6":1.5,
"qwen3-embedding":0.5,"gemma4":1.5}'

if [ -n "${NAN_USAGE_FILE:-}" ]; then
  usage=$(cat "$NAN_USAGE_FILE") || { echo "nan-usage: cannot read $NAN_USAGE_FILE" >&2; exit 1; }
else
  key=${NAN_API_KEY:-}
  if [ -z "$key" ]; then
    key=$(jq -r '.providers.nan.apiKey // empty' "$HOME/.pi/agent/models.json" 2>/dev/null)
    [ -n "$key" ] || { echo "nan-usage: no NAN key: set NAN_API_KEY or .providers.nan.apiKey in ~/.pi/agent/models.json" >&2; exit 1; }
  fi
  case $key in '!'*) key=$(sh -c "${key#!}") ;; esac
  [ -n "$key" ] || { echo "nan-usage: the NAN key command printed nothing" >&2; exit 1; }
  usage=$(curl -sS --max-time 20 -K <(printf 'header = "authorization: Bearer %s"\n' "$key") \
    https://api.nan.builders/v1/usage) || { echo "nan-usage: cannot reach NAN" >&2; exit 1; }
fi
jq -e '.data' >/dev/null 2>&1 <<<"$usage" || { echo "nan-usage: bad answer from NAN: ${usage:0:200}" >&2; exit 1; }
today=$(date +%Y-%m-%d)

if [ "${1:-}" = set ]; then
  left=${2:?usage: nan-usage set <credits left>}
  mkdir -p "$(dirname "$state")"
  jq -n --arg d "$today" --argjson left "$left" --argjson u "$usage" \
    '{date: $d, left: $left, set_at: (now | todate),
      seen: ([$u.data[] | select(.date == $d) | {(.model): .total_tokens}] | add // {})}' >"$state"
  echo "anchored: $left credits left on $today"
  exit 0
fi
[ -f "$state" ] || { echo "nan-usage: run 'nan-usage set <credits left>' first (NAN dashboard)" >&2; exit 1; }

jq -r --argjson s "$(cat "$state")" --argjson r "$rates" --argjson period "$period" --argjson warn "$warn" \
  --arg today "$today" --arg quiet "${1:-}" '
  def cr: .total_tokens / 1e6 * ($r[.model] // 25);
  [.data[] | select(.date > $s.date)] as $after
  | [.data[] | select(.date == $s.date) | .total_tokens -= ($s.seen[.model] // 0) | select(.total_tokens > 0)] as $anchorday
  | (($after + $anchorday) | map(cr) | add // 0) as $spent
  | ($s.left - $spent) as $left
  | ([.data[] | select(.date == $today) | cr] | add // 0) as $day
  | ([.data[] | select(.date > ($today | strptime("%Y-%m-%d") | mktime - 6*86400 | strftime("%Y-%m-%d"))) | cr] | add // 0) as $week
  | ($left / $period * 100) as $pct
  | (if $week > 0 then $left / ($week / 7) else null end) as $days
  | if $quiet == "--quiet" then
      "NAN \($left | floor)/\($period) cr (\($pct | floor)%)"
    else
      "NAN credits left ≈ \($left | floor) / \($period)  (\($pct | floor)%)",
      "  spent since anchor \($s.date): \($spent | round)",
      "  today: \($day | round)   last 7 days: \($week | round)",
      (if $days then "  at the 7-day pace: ~\($days | floor) days left" else empty end),
      (if $pct < $warn then "  WARNING: under \($warn)% — buy a pack or turn on auto-recharge" else empty end)
    end,
    (if $pct < $warn then "__LOW__" else empty end)' <<<"$usage" | {
  low=0
  while IFS= read -r line; do
    [ "$line" = __LOW__ ] && { low=1; continue; }
    echo "$line"
  done
  exit $((low * 2))
}
