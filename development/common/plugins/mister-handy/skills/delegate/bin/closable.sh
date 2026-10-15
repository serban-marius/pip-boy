#!/bin/bash
# closable.sh <worktree path>: CLOSABLE when removing it loses nothing, else KEEP <why>.

wt=${1:?usage: closable.sh <worktree path>}
git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || { echo "KEEP not a git worktree: $wt"; exit 1; }

head_of_merged_pr() {
  local branch
  branch=$(git -C "$wt" branch --show-current)
  [ -n "$branch" ] || return 1
  (cd "$wt" && gh pr list --head "$branch" --state merged --json headRefOid -q '.[].headRefOid' 2>/dev/null) |
    grep -qx "$(git -C "$wt" rev-parse HEAD)"
}

why=""
[ -z "$(git -C "$wt" status --porcelain)" ] || why="$why; uncommitted changes"
[ -z "$(git -C "$wt" rev-list -n 1 HEAD --not --remotes)" ] || head_of_merged_pr ||
  why="$why; commits on no remote branch and no merged PR with this head"

[ -z "$why" ] && { echo CLOSABLE; exit 0; }
echo "KEEP ${why#; }"
exit 1
