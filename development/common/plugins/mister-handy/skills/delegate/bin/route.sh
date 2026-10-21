#!/bin/bash
# route.sh <brief>: which agent takes this brief. Prints <agent> <model> <confidence> <reason>.
# Claude without asking Jev: no Acceptance, Risk missing or high, a production write. Then Jev; an
# error, or an answer under the threshold (MISTER_HANDY_ROUTE_THRESHOLD, default 0.6), goes one tier up.
# Key: TYPESAFE_API_KEY, else the keychain item "jev". Never printed.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
brief=${1:?usage: route.sh <brief>}
[ -f "$brief" ] || { echo "no brief: $brief" >&2; exit 1; }
threshold=${MISTER_HANDY_ROUTE_THRESHOLD:-0.6}

pick() {
  case $1 in
    0) echo "pi $(ladder | awk '{ print $1; exit }') $2 $3" ;;
    1) echo "claude sonnet $2 $3" ;;
    *) echo "claude opus $2 $3" ;;
  esac
  exit 0
}

[ -n "$(brief_acceptance "$brief")" ] || pick 2 1.00 no-acceptance
case $(brief_risk "$brief") in
  low | normal) ;;
  high) pick 2 1.00 risk-high ;;
  *) pick 2 1.00 no-risk ;;
esac
[ -z "$(brief_prod "$brief")" ] || pick 2 1.00 production

key=${TYPESAFE_API_KEY:-$(security find-generic-password -s jev -w 2>/dev/null)}
[ -n "$key" ] || pick 2 0.00 jev-no-key

body=$(jq -n --rawfile brief "$brief" '{
  model: "jev-latest",
  state: { brief: $brief[0:96000] },
  questions: { agent: {
    type: "choice",
    stakes: "design",
    instructions: "Pick the cheapest coding agent that will very likely complete this task correctly on its first attempt. The task is accepted only when every command in its Acceptance section exits 0.",
    criteria: {
      "nan-flash": "A small open-source model running headless with read, bash, edit and write tools. Fits well-specified, local, mechanical changes: few files, the change spelled out, runnable acceptance commands, no design judgement, no cross-system reasoning, no production access.",
      "claude-sonnet": "A strong general coding agent. Fits multi-file features and bug fixes with some ambiguity, unfamiliar code to understand first, or tests to design, where the design is mostly given.",
      "claude-opus": "The strongest and most expensive agent. Fits open-ended design, subtle debugging, security- or money-sensitive work, large refactors, and briefs whose success depends on judgement."
    }
  } }
}')

reply=$(printf '%s' "$body" | curl -sS --max-time "${MISTER_HANDY_ROUTE_TIMEOUT:-10}" -w '\n%{http_code}' \
  -K <(printf 'header = "authorization: Bearer %s"\n' "$key") \
  -H 'content-type: application/json' --data-binary @- https://api.typesafe.ai/v1/systemone 2>/dev/null)
rc=$?
[ "$rc" -eq 28 ] && pick 2 0.00 jev-timeout
[ "$rc" -eq 0 ] || pick 2 0.00 jev-error
[ "$(tail -n 1 <<<"$reply")" = 200 ] || pick 2 0.00 jev-http-$(tail -n 1 <<<"$reply")

read -r choice conf < <(sed '$d' <<<"$reply" | jq -r '.answers.agent | "\(.choice) \(.confidence)"' 2>/dev/null)
case $choice in
  nan-flash) tier=0 ;;
  claude-sonnet) tier=1 ;;
  claude-opus) tier=2 ;;
  *) pick 2 0.00 jev-undecided ;;
esac
awk -v c="$conf" 'BEGIN { exit !(c + 0 == c && c >= 0 && c <= 1) }' || pick 2 0.00 jev-undecided
conf=$(awk -v c="$conf" 'BEGIN { printf "%.2f", c }')
awk -v c="$conf" -v t="$threshold" 'BEGIN { exit !(c < t) }' && pick $((tier < 2 ? tier + 1 : 2)) "$conf" "low-confidence:$choice"
pick "$tier" "$conf" jev
