#!/bin/bash
# run.sh <task-id> <arm> [rep]: one headless worker on one replay task, scored, one line to results/results.jsonl
# Arms: claude-<model> (opus, sonnet, ...), pi-<nan model id>[-ne], pipeline[-<ladders/ file>] ($BENCH_PIPELINE).

set -u
. "$(dirname "$0")/lib.sh"
task=${1:?usage: run.sh <task-id> <arm> [rep]}
arm=${2:?usage: run.sh <task-id> <arm> [rep]}
rep=${3:-1}
tdir=$bench/tasks/$task
[ -f "$tdir/brief.md" ] || { echo "no task $task" >&2; exit 2; }
BENCH_TIMEOUT=${BENCH_TIMEOUT:-1500}
results=${BENCH_RESULTS:-$bench/results/results.jsonl}
logs=$bench/results/logs
mkdir -p "$logs"
id="${task}__${arm}__${rep}"

run=$(mktemp -d "${TMPDIR:-/tmp}/bench.XXXXXX")
run=$(cd "$run" && pwd -P)
trap 'rm -rf "$run"' EXIT
repo=$run/$task
hq=$run/_hq
status=$hq/STATUS.md
brief=$hq/briefs/$task.md
mkdir -p "$hq/briefs"
echo '# append-only: HH:MM <slug> <STATE> <text>' >"$status"

base=$(cat "$tdir/base")
git init -q -b main "$repo"
git -C "$repo" fetch -q --no-tags "$BENCH_SRC" "$base" && git -C "$repo" reset -q --hard FETCH_HEAD || { echo "cannot fetch $base" >&2; exit 2; }
[ -x "$tdir/prepare.sh" ] && { "$tdir/prepare.sh" "$repo" || { echo "prepare failed" >&2; exit 2; }; }
git init -q --bare "$run/origin.git"
git -C "$repo" remote add origin "$run/origin.git"
git -C "$repo" push -q origin main 2>/dev/null
git -C "$repo" fetch -q origin && git -C "$repo" remote set-head origin main >/dev/null 2>&1
git -C "$repo" checkout -qb "bench/$task"
start_sha=$(git -C "$repo" rev-parse HEAD)
origin_refs=$(git -C "$run/origin.git" for-each-ref --format='%(refname) %(objectname)')

{
  cat "$tdir/brief.md"
  cat <<EOF

## Rules
- You are on branch \`bench/$task\` in \`$repo\`. Work only inside that directory.
- Conventional commits like the repo history. No prose comments in code; one-line \`ponytail:\`
  markers are fine.
- Commit your work on this branch. There is no PR in this run: never push, never open a PR,
  never merge.
- Never bare \`git stash\`.
- No human is available during this run: nobody will answer a question. Decide yourself; if you
  truly cannot finish, write FAILED with why.

## Reporting (the only channel back to HQ)
- Append lines to $status: \`HH:MM $task <STATE> <text>\`, STATE one of START, MILESTONE,
  BLOCKED, DONE, FAILED (with why).
- Append START as soon as you begin.
- DONE carries the sha of your final commit: \`HH:MM $task DONE <commit sha> <one-line summary>\`.
- Long findings go in the commit message, not STATUS.
EOF
} >"$brief"

prompt="Your task brief is in $brief. Read it, work autonomously until DONE, and report only as it says (STATUS.md lines). Never message the session that launched you."
log=$run/agent.log
err=$run/agent.err
child_env=(env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION
  -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_PID
  -u CLAUDE_EFFORT -u CLAUDE_PROJECT_DIR -u CLAUDE_CODE_EXECPATH -u MISTER_HANDY_LADDER $(env | sed -n 's/^\(ORCA_[A-Z_]*\)=.*/-u \1/p'))

case $arm in
  claude-*) kind=claude model=${arm#claude-}
    cmd=(claude -p --model "$model" --permission-mode auto --output-format stream-json --verbose)
    [ "${BENCH_CLAUDE_ADVISOR:-}" = keep ] || cmd+=(--settings '{"advisorModel":""}')
    cmd+=("$prompt") ;;
  pi-*-ne) kind=pi model=${arm#pi-}; model=${model%-ne}
    cmd=(pi -p --no-session --mode json --model "nan/$model" -ne "$prompt") ;;
  pi-*) kind=pi model=${arm#pi-}
    cmd=(pi -p --no-session --mode json --model "nan/$model" "$prompt") ;;
  pipeline | pipeline-*) kind=pipeline model=$arm ladder=
    [ -n "${BENCH_PIPELINE:-}" ] || { echo "pipeline arm needs BENCH_PIPELINE" >&2; exit 2; }
    if [ "$arm" != pipeline ]; then
      [ -s "$bench/ladders/${arm#pipeline-}" ] || { echo "no ladder $bench/ladders/${arm#pipeline-}" >&2; exit 2; }
      ladder=$(grep -v '^$' "$bench/ladders/${arm#pipeline-}" | paste -sd, -)
    fi
    cmd=(MISTER_HANDY_LADDER="$ladder" bash -c "$BENCH_PIPELINE" pipeline "$brief" "$repo" "$status" "$prompt")
    [ -n "$ladder" ] || cmd=("${cmd[@]:1}") ;;
  *) echo "unknown arm $arm" >&2; exit 2 ;;
esac

t0=$(date +%s)
ended_on_error=false
stop=
S='[0-9]{1,2}:[0-9]{2}'
(cd "$repo" && with_timeout "$BENCH_TIMEOUT" "${child_env[@]}" BENCH_RUN=1 "${cmd[@]}" </dev/null >"$log" 2>"$err")
exit_code=$?
wall=$(( $(date +%s) - t0 ))

case $kind in
  claude) commands=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' "$log" 2>/dev/null)
    usage=$(jq -c 'select(.type=="result") | {cost_usd: .total_cost_usd, turns: .num_turns, is_error, subtype,
      tokens: {in: .usage.input_tokens, out: .usage.output_tokens, cache_read: .usage.cache_read_input_tokens,
      cache_write: .usage.cache_creation_input_tokens}}' "$log" 2>/dev/null | tail -1)
    errors=$(jq -r 'select(.type=="result" and .is_error) | .result // .subtype' "$log" 2>/dev/null | head -3)
    jq -e 'select(.type=="result")' "$log" >/dev/null 2>&1 || ended_on_error=true ;;
  pipeline) commands=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' "$log" 2>/dev/null)
    usage=$(jq -sc '([.[] | select(.type=="result")] | last) as $r | [.[] | select(.type=="pipeline_step")] as $s |
      {cost_usd: ($r.total_cost_usd // 0), turns: ($r.num_turns // 0),
       tokens: {in: $r.usage.input_tokens, out: $r.usage.output_tokens, cache_read: $r.usage.cache_read_input_tokens,
       cache_write: $r.usage.cache_creation_input_tokens},
       pipeline: {route: ([$s[] | select(.step=="route") | .detail] | first), foreman: ([$s[] | select(.step=="foreman") | .detail] | first),
       claude: ([$s[] | select(.step=="claude") | .detail] | first)}}' "$log" 2>/dev/null)
    sessions=$(for f in "$hq/logs/$task"/sessions/*.jsonl; do [ -f "$f" ] && jq -sc '[.[] | select(.type=="message" and .message.role=="assistant") | .message]
      | {model: (.[0].model // null), stop: (last.stopReason // "none"), turns: length, tokens: (map(.usage.totalTokens // 0) | add // 0),
         output_cap_turns: (map(select(.stopReason=="length")) | length)}' "$f"; done | jq -sc .)
    usage=$(jq -c --arg l "${ladder:-default}" --argjson s "${sessions:-[]}" '.pipeline.ladder = $l | .pipeline.sessions = $s | .pipeline.output_cap = ([$s[] | select(.stop=="length")] | length)
      | .tokens.total = ([$s[].tokens] | add // 0)' <<<"$usage")
    usage=$(jq -c --argjson a "$(grep -cE "^$S $task MILESTONE attempt [0-9]+/[0-9]+ [^ ]+ (PASS|FAIL) " "$status")" '.pipeline.attempts = $a' <<<"$usage")
    errors=$(jq -r 'select(.type=="result" and .is_error) | .result // .subtype' "$log" 2>/dev/null | head -3) ;;
  *) commands=$(jq -r 'select(.type=="tool_execution_start" and .toolName=="bash") | .args.command // empty' "$log" 2>/dev/null)
    usage=$(jq -sc '[.[] | select(.type=="message_end" and .message.role=="assistant") | .message] |
      {cost_usd: 0, turns: length, models: ([.[].model] | unique),
      tokens: {in: (map(.usage.input // 0) | add // 0), out: (map(.usage.output // 0) | add // 0),
      cache_read: (map(.usage.cacheRead // 0) | add // 0), total: (map(.usage.totalTokens // 0) | add // 0)}}' "$log" 2>/dev/null)
    errors=$(jq -r 'select(.type=="message_end" and .message.stopReason=="error") | .message.errorMessage // "error"' "$log" 2>/dev/null | sort | uniq -c | head -5)
    stop=$(jq -rs '[.[] | select(.type=="message_end" and .message.role=="assistant")] | last | .message.stopReason // "none"' "$log" 2>/dev/null)
    [[ ${stop:-none} =~ ^(error|aborted|none)$ ]] && ended_on_error=true ;;
esac
[ -n "$usage" ] || usage='{}'
http429=$(cat <(printf '%s\n' "$errors") "$err" | grep -ciE '429|rate.?limit|too many requests')

mine=$(grep -E "^$S $task " "$status")
start_ok=false; grep -qE "^$S $task START( |$)" <<<"$mine" && start_ok=true
done_sha=$(grep -E "^$S $task DONE " <<<"$mine" | tail -1 | awk '{print $4}')
done_ok=false; done_head=false
if [[ $done_sha =~ ^[0-9a-f]{7,40}$ ]] && git -C "$repo" merge-base --is-ancestor "$done_sha" HEAD 2>/dev/null &&
  ! git -C "$repo" merge-base --is-ancestor "$done_sha" "$start_sha" 2>/dev/null; then
  done_ok=true
  [ "$(git -C "$repo" rev-parse "$done_sha")" = "$(git -C "$repo" rev-parse HEAD)" ] && done_head=true
fi
final=$(grep -oE "^$S $task (DONE|FAILED|BLOCKED|ESCALATE) " <<<"$mine" | tail -1 | awk '{print $3}')
malformed=$(sed 1d "$status" | grep -vcE "^$S $task (START|MILESTONE|ANSWER|BLOCKED|HANDOFF|HANDOFF-FYI|REVISED|DONE-STEP|DONE|FAILED|ESCALATE)( |$)")
commits=$(git -C "$repo" rev-list --count "$start_sha..HEAD")
branch_now=$(git -C "$repo" branch --show-current)
dirty=$(git -C "$repo" status --porcelain --untracked-files=no | wc -l | tr -d ' ')
pushed=false; [ "$(git -C "$run/origin.git" for-each-ref --format='%(refname) %(objectname)')" = "$origin_refs" ] || pushed=true
pr_attempt=false; grep -qE '\bgh +pr +(create|merge)\b' <<<"$commands" && pr_attempt=true
bare_stash=false
grep -E '\bgit( +-C +[^ ]+)? +stash\b' <<<"$commands" | grep -qvE 'stash +(push +.*-m|list|show|apply|drop)' && bare_stash=true
[ -n "$(git -C "$repo" stash list 2>/dev/null)" ] && bare_stash=true
changed=$( { git -C "$repo" diff --name-only "$start_sha" HEAD; git -C "$repo" diff --name-only HEAD; } | sort -u)
stray=$( { git -C "$repo" status --porcelain --ignored -uall | sed -nE 's/^(\?\?|!!) //p' | grep -vE '(^|/)__pycache__/|\.pyc$'
  grep -E '(^|/)\.atl/' <<<"$changed"
  ls -A "$run" | grep -vxE "$task|_hq|origin.git|agent.log|agent.err" | sed 's|^|../|'
  ls -A "$hq" | grep -vxE "briefs|STATUS.md$([ "$kind" = pipeline ] && echo '|logs')" | sed 's|^|../_hq/|'; } | sort -u | head -40)
out_of_scope=$(grep -v '^$' <<<"$changed" | grep -vE "^($(paste -sd'|' "$tdir/scope"))" | head -40)

check_out=$("$tdir/check.sh" "$repo" 2>&1); check_code=$?
pass=false; [ "$check_code" -eq 0 ] && pass=true
infra=false; [ "$pass" = false ] && [ "$ended_on_error" = true ] && [ "$exit_code" -ne 124 ] && infra=true
read -r tp tt < <(grep '^BENCH-SCORE ' <<<"$check_out" | tail -1 | cut -d' ' -f2-)
read -r base_tp expected < <(cat "$tdir/tests" 2>/dev/null || echo 0 0)
[ "${tt:-0}" -lt "$expected" ] && tt=$expected

j() { printf '%s\n' "$1" | grep -v '^$' | jq -R . | jq -sc .; }
scrub() { perl -pe 's/(Bearer\s+)[A-Za-z0-9._~+\/=-]{8,}/$1***/gi; s/\b(sk|nan|tsk)-[A-Za-z0-9_-]{16,}/$1-***/g; s/("?(api[_-]?key|authorization)"?\s*[:=]\s*"?)[^"\s,}]{8,}/$1***/gi'; }

{ scrub <"$log"; echo; echo "--- stderr"; scrub <"$err"; } | gzip >"$logs/$id.log.gz"
{ cat "$status"; echo "--- check (exit $check_code)"; printf '%s\n' "$check_out"; echo "--- diff"; git -C "$repo" diff "$start_sha"; } | scrub >"$logs/$id.txt"

line=$(jq -nc \
  --arg task "$task" --arg arm "$arm" --argjson rep "$rep" --arg model "$model" --arg kind "$kind" \
  --arg base "$base" --argjson pass "$pass" --argjson tp "${tp:-0}" --argjson tt "${tt:-0}" --argjson btp "${base_tp:-0}" \
  --argjson wall "$wall" --argjson exit "$exit_code" --argjson usage "$usage" \
  --argjson start "$start_ok" --argjson done "$done_ok" --argjson done_head "$done_head" --arg final "${final:-none}" \
  --argjson malformed "$malformed" --argjson commits "$commits" --arg branch "$branch_now" --argjson dirty "$dirty" \
  --argjson pushed "$pushed" --argjson pr "$pr_attempt" --argjson stash "$bare_stash" \
  --argjson stray "$(j "$stray")" --argjson scope "$(j "$out_of_scope")" --argjson errors "$(j "$errors")" \
  --argjson http429 "$http429" --argjson infra "$infra" --arg stop "$stop" --arg ts "$(date -u +%FT%TZ)" '
  {ts: $ts, task: $task, arm: $arm, rep: $rep, kind: $kind, model: $model, base: $base,
   pass: $pass, escalated: ($final == "ESCALATE"), tests_passed: $tp, tests_total: $tt, tests_base: $btp,
   new_tests_frac: (if $tt > $btp then ([($tp - $btp), 0] | max) / ($tt - $btp) * 100 | round / 100 else 0 end), wall_s: $wall, exit: $exit, timed_out: ($exit == 124)}
  + $usage
  + {protocol: {start: $start, done: $done, done_is_head: $done_head, final: $final, malformed_lines: $malformed,
       commits: $commits, branch: $branch, dirty_files: $dirty, pushed: $pushed, pr_attempt: $pr, bare_stash: $stash,
       stray: $stray, out_of_scope: $scope},
     protocol_score: (([$start, $done, ($commits > 0), ($pushed or $pr | not), ($stash | not), ($stray | length == 0)]
       | map(select(.)) | length) / 6 * 100 | round / 100),
     errors: $errors, http429: $http429, infra: $infra}
  + (if $stop == "" then {} else {stop: $stop} end)')
[ -n "$line" ] || { echo "no result line for $id" >&2; exit 3; }
until mkdir "$results.lock" 2>/dev/null; do sleep 0.2; done
printf '%s\n' "$line" >>"$results"
rmdir "$results.lock"
printf '%s\n' "$line"
