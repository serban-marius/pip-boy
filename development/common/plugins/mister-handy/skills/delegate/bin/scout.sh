#!/bin/bash
here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
repo=${1:?usage: scout.sh <repo dir> <question file> [out file]}
question=${2:?usage: scout.sh <repo dir> <question file> [out file]}
out=${3:-}
scout_timeout=${MISTER_HANDY_SCOUT_TIMEOUT:-600}
limit_pl='$t = shift; $p = fork; if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 } setpgrp($p, $p);
  $SIG{ALRM} = sub { kill "TERM", -$p; sleep 2; kill "KILL", -$p; exit 142 }; alarm $t;
  waitpid($p, 0); $rc = $?; alarm 0; kill "TERM", -$p; exit($rc & 127 ? 128 + ($rc & 127) : $rc >> 8)'

pi_rung=""
claude_rung=""
while read -r rung _; do
  case $rung in
    pi:*) [ -n "$pi_rung" ] || pi_rung=$rung ;;
    claude:*) [ -n "$claude_rung" ] || claude_rung=$rung ;;
  esac
done < <(ladder)
rung=${pi_rung:-$claude_rung}
if [ -z "$rung" ]; then
  echo "scout: the ladder has no pi: or claude: rung" >&2
  exit 2
fi
runner=${rung%%:*}
model=${rung#*:}
command -v "$runner" >/dev/null || { echo "scout: $runner is not installed" >&2; exit 2; }

[ -f "$question" ] || { echo "scout: no question file at $question" >&2; exit 2; }
question=$(cd "$(dirname "$question")" && pwd)/$(basename "$question")
if [ -n "$out" ]; then
  out=$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out") ||
    { echo "scout: no directory for $3" >&2; exit 2; }
fi
repo=$(cd "$repo" 2>/dev/null && pwd) || { echo "scout: no repo at $1" >&2; exit 2; }
cd "$repo" || exit 2

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
promptf=$tmp/prompt
answer=$tmp/answer
{
  cat "$question"
  cat <<'EOF'

Investigate this repository read-only and answer with a section '## What we already know': the files and functions involved with paths and line numbers, how it behaves today, the tests that cover it and how to run them, and open questions. Facts only, no plan, at most 60 lines.
EOF
} >"$promptf"
prompt=$(cat "$promptf")

if [ "$runner" = pi ]; then
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY \
    perl -e "$limit_pl" "$scout_timeout" pi -p -ne --no-session --tools read,grep,find,ls \
      --model "$model" "$prompt" </dev/null >"$answer"
  rc=$?
else
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY \
    perl -e "$limit_pl" "$scout_timeout" claude -p --model "$model" \
      --settings '{"advisorModel":""}' --output-format text --no-session-persistence --strict-mcp-config \
      --tools Read,Grep,Glob --allowedTools Read,Grep,Glob --permission-mode dontAsk \
      "$prompt" </dev/null >"$answer"
  rc=$?
fi

if [ "$rc" -ne 0 ]; then
  [ "$rc" -ne 142 ] || echo "scout: timed out after ${scout_timeout}s" >&2
  exit "$rc"
fi
if ! grep -q '[^[:space:]]' "$answer"; then
  echo "scout: empty answer from $rung" >&2
  exit 1
fi
if [ -n "$out" ]; then
  cat "$answer" >"$out" || exit 2
else
  cat "$answer"
fi
