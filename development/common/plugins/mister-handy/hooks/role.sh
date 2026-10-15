#!/bin/bash
# SessionStart: HQ = default branch or outside git; any other branch or detached HEAD = worker.
# MISTER_HANDY=off|hq|worker overrides.

[ "${MISTER_HANDY:-}" = off ] && exit 0
cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0

backend=subagents
[ -n "${ORCA_AGENT_SESSION_ID:-}${ORCA_CLI_COMMAND:-}" ] && backend=orca

role=hq
branch=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git branch --show-current 2>/dev/null)
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  default=${default#origin/}
  case "$branch" in
    "${default:-main}"|main|master) ;;
    *) role=worker ;;
  esac
fi
case "${MISTER_HANDY:-}" in hq|worker) role=$MISTER_HANDY ;; esac

if [ "$role" = hq ]; then
  where=${branch:+"on $branch"}
  cat <<MSG
mister-handy: this session is HQ (${where:-outside a git repo}; backend: $backend).
By default, every substantive task the user gives goes out through the mister-handy:delegate skill, even when they do not mention worktrees or agents: investigations, code changes, PRs, reviews, deploy watches, anything that needs more than a few reads. Load the skill and follow its $backend path, and keep its watcher armed (Mode 6) until every task you launched has settled: you orchestrate what you launch.
Stay here only for answers from what is already in context, reading just enough to write a brief, and one-minute chores the user asks for directly (a commit, a push, a one-line tweak). Status questions are answered from _hq/STATUS.md, never from worker transcripts.
If the user says to do something here ("hazlo aquí", "do it in this session"), do it here.
MSG
else
  label=${branch:+branch $branch}
  label=${label:-detached HEAD}
  cat <<MSG
mister-handy: this session is a worker ($label).
Do the task here yourself; do not hand it on to another worktree or delegate it with mister-handy:delegate. Subagents inside this worktree for parallel reads are fine.
If you were given a brief from _hq/briefs/, report exactly as it says.
MSG
fi
