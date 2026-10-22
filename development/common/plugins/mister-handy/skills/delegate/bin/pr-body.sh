#!/bin/bash
# pr-body.sh <brief> <base sha> [out file]

here=$(cd "$(dirname "$0")" && pwd)
. "$here/brief.sh"
load_config

brief=${1:?usage: pr-body.sh <brief> <base sha> [out file]}
base=${2:?usage: pr-body.sh <brief> <base sha> [out file]}
out=${3:-}
pr_body_timeout=${MISTER_HANDY_PR_BODY_TIMEOUT:-600}
limit_pl='$t = shift; $p = fork; if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 } setpgrp($p, $p);
  $SIG{ALRM} = sub { kill "TERM", -$p; sleep 2; kill "KILL", -$p; exit 142 }; alarm $t;
  waitpid($p, 0); $rc = $?; alarm 0; kill "TERM", -$p; exit($rc & 127 ? 128 + ($rc & 127) : $rc >> 8)'

[ -f "$brief" ] || { echo "pr-body: no brief at $brief" >&2; exit 2; }
brief=$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "pr-body: not a git worktree" >&2; exit 2; }
git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || { echo "pr-body: no commit at $base" >&2; exit 2; }
if [ -n "$out" ]; then
  out=$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out") ||
    { echo "pr-body: no directory for $3" >&2; exit 2; }
fi

pi_rung=""
claude_rung=""
while read -r rung _; do
  case $rung in
    pi:*) [ -n "$pi_rung" ] || pi_rung=$rung ;;
    claude:*) [ -n "$claude_rung" ] || claude_rung=$rung ;;
  esac
done < <(ladder)
rung=${pi_rung:-$claude_rung}

template() {
  cat <<'EOF'
Write the GitHub pull request description for the change below. Output ONLY the markdown body, no preamble.
Audience: a reviewer who has not seen the brief. Be concrete and short; no marketing words.
Structure exactly:
## What
2-4 sentences: what this PR adds and why (from the brief's Why).
## How it works
Bullets: the main components and files (paths in backticks), data flow, key design choices (schema, chunking, embedding, search/rerank, auth, retries). Mention config/env vars by name, never their values.
## How to run it
A fenced bash block with the commands to build/run/test, taken from the diff (README/scripts/Dockerfile).
## Tests
Bullets: what the tests cover (name the areas), and how they run.
## Review notes
Bullets: anything a reviewer should look at (assumptions, limits, things deliberately left out, follow-ups) that the brief or diff shows. Do not invent.
Rules: every command or shell snippet goes inside a fenced code block (never inline `$...$`, GitHub renders that as math). No secrets. Under 70 lines.
EOF
}

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
promptf=$tmp/prompt
answer=$tmp/answer
body=$tmp/body

{
  template
  printf '\n\n## The brief\n\n'
  brief_without "$brief" Reporting | grep -v '^PR:'
  printf '\n\n## Commits\n\n```text\n'
  git log --format=%s "$base"..HEAD
  printf '```\n\n## The diff\n\n'
  if [ "$(git diff "$base"..HEAD | wc -c | tr -d ' ')" -gt 300000 ]; then
    git diff --stat "$base"..HEAD
    printf '\n'
    sizes=()
    while IFS=$'\t' read -r added deleted path; do
      case $added in '' | *[!0-9]*) continue ;; esac
      case $deleted in '' | *[!0-9]*) continue ;; esac
      sizes+=("$((added + deleted))"$'\t'"$path")
    done < <(git diff --numstat "$base"..HEAD)
    if [ "${#sizes[@]}" -gt 0 ]; then
      printf '%s\n' "${sizes[@]}" | sort -rn | head -n 15 | cut -f2- >"$tmp/files"
      files=()
      while IFS= read -r path; do [ -z "$path" ] || files+=("$path"); done <"$tmp/files"
      if [ "${#files[@]}" -gt 0 ]; then
        git diff "$base"..HEAD -- "${files[@]}" | head -c 300000
      fi
    fi
  else
    git diff "$base"..HEAD
  fi
} >"$promptf"

: >"$answer"
if [ -z "$rung" ]; then
  rc=1
elif ! command -v "${rung%%:*}" >/dev/null; then
  rc=127
elif [ "${rung%%:*}" = pi ]; then
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY \
    perl -e "$limit_pl" "$pr_body_timeout" pi -p --no-session -ne --no-tools \
      --model "${rung#*:}" "$(cat "$promptf")" </dev/null >"$answer"
  rc=$?
else
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u TYPESAFE_API_KEY \
    perl -e "$limit_pl" "$pr_body_timeout" claude -p --model "${rung#*:}" --tools "" \
      --settings '{"advisorModel":""}' "$(cat "$promptf")" </dev/null >"$answer"
  rc=$?
fi

if [ "$rc" -eq 0 ] && [ -s "$answer" ] && grep -qE '^## What[[:space:]]*$' "$answer"; then
  cat "$answer" >"$body"
else
  {
    echo '## What'
    echo
    brief_section "$brief" Why
    echo
    echo '## Changes'
    echo
    echo '```text'
    git diff --stat "$base"
    echo '```'
  } >"$body"
fi

if [ -n "$out" ]; then
  cat "$body" >"$out" || exit 2
else
  cat "$body"
fi
