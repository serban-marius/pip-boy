#!/bin/bash
# route.sh <brief>: which agent takes this brief. Prints <agent> <model> <confidence> <reason>.
# Tiers: cheap = "foreman <ladder head>", mid = MISTER_HANDY_MID (claude sonnet), top = MISTER_HANDY_TOP (claude opus).
# Top without asking: no runnable Acceptance, Risk missing or high, a production write. Then the router,
# MISTER_HANDY_ROUTER=jev|rules (default jev when a key is found, else rules). rules: everything left is cheap.
# jev: an error is mid, an answer under MISTER_HANDY_ROUTE_THRESHOLD (0.6) goes one tier up,
# except a cheap answer when MISTER_HANDY_ADVISOR is set: then MISTER_HANDY_ROUTE_THRESHOLD_ADVISED (0.3).
# Jev key: TYPESAFE_API_KEY, else the macOS keychain item "jev". Never printed.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
brief=${1:?usage: route.sh <brief>}
[ -f "$brief" ] || { echo "no brief: $brief" >&2; exit 1; }
threshold=${MISTER_HANDY_ROUTE_THRESHOLD:-0.6}

pick() {
  case $1 in
    0) head=$(ladder | awk '{ print $1; exit }')
      [ -n "$head" ] && echo "foreman $head $2 $3" || echo "${MISTER_HANDY_MID:-claude sonnet} $2 empty-ladder" ;;
    1) echo "${MISTER_HANDY_MID:-claude sonnet} $2 $3" ;;
    *) echo "${MISTER_HANDY_TOP:-claude opus} $2 $3" ;;
  esac
  exit 0
}

[ -n "$(brief_acceptance "$brief")" ] || pick 2 1.00 no-acceptance
brief_lint "$brief" >/dev/null || pick 2 1.00 acceptance-not-runnable
case $(brief_risk "$brief") in
  low | normal) ;;
  high) pick 2 1.00 risk-high ;;
  *) pick 2 1.00 no-risk ;;
esac
[ -z "$(brief_prod "$brief")" ] || pick 2 1.00 production

router=${MISTER_HANDY_ROUTER:-}
key=""
[ "$router" = rules ] || key=${TYPESAFE_API_KEY:-$(security find-generic-password -s jev -w 2>/dev/null)}
[ -n "$router" ] || router=$([ -n "$key" ] && echo jev || echo rules)
case $router in
  rules) pick 0 1.00 rules ;;
  jev) ;;
  *) echo "MISTER_HANDY_ROUTER must be jev or rules, not $router" >&2; exit 1 ;;
esac
[ -n "$key" ] || pick 1 0.00 jev-no-key

body=$(jq -n --rawfile brief "$brief" '{
  model: "jev-latest",
  state: { brief: $brief[0:96000] },
  questions: { agent: {
    type: "choice",
    stakes: "design",
    instructions: "Pick the cheapest coding agent that will very likely complete this task correctly on its first attempt. The task is accepted only when every command in its Acceptance section exits 0.",
    criteria: {
      "cheap": "A small, cheap model running headless with read, bash, edit and write tools, retried by a script on failure. Fits well-specified, local, mechanical changes: few files, the change spelled out, runnable acceptance commands, no design judgement, no cross-system reasoning, no production access.",
      "mid": "A strong general coding agent. Fits multi-file features and bug fixes with some ambiguity, unfamiliar code to understand first, or tests to design, where the design is mostly given.",
      "top": "The strongest and most expensive agent. Fits open-ended design, subtle debugging, security- or money-sensitive work, large refactors, and briefs whose success depends on judgement."
    }
  } }
}')

reply=$(printf '%s' "$body" | curl -sS --max-time "${MISTER_HANDY_ROUTE_TIMEOUT:-10}" -w '\n%{http_code}' \
  -K <(printf 'header = "authorization: Bearer %s"\n' "$key") \
  -H 'content-type: application/json' --data-binary @- https://api.typesafe.ai/v1/systemone 2>/dev/null)
rc=$?
[ "$rc" -eq 28 ] && pick 1 0.00 jev-timeout
[ "$rc" -eq 0 ] || pick 1 0.00 jev-error
[ "$(tail -n 1 <<<"$reply")" = 200 ] || pick 1 0.00 jev-http-$(tail -n 1 <<<"$reply")

read -r choice conf < <(sed '$d' <<<"$reply" | jq -r '.answers.agent | "\(.choice) \(.confidence)"' 2>/dev/null)
case $choice in
  cheap) tier=0 ;;
  mid) tier=1 ;;
  top) tier=2 ;;
  *) pick 1 0.00 jev-undecided ;;
esac
awk -v c="$conf" 'BEGIN { exit !(c + 0 == c && c >= 0 && c <= 1) }' || pick 1 0.00 jev-undecided
conf=$(awk -v c="$conf" 'BEGIN { printf "%.2f", c }')
[ "$choice" != cheap ] || [ -z "${MISTER_HANDY_ADVISOR:-}" ] || threshold=${MISTER_HANDY_ROUTE_THRESHOLD_ADVISED:-0.3}
awk -v c="$conf" -v t="$threshold" 'BEGIN { exit !(c < t) }' && pick $((tier < 2 ? tier + 1 : 2)) "$conf" "low-confidence:$choice"
pick "$tier" "$conf" jev
