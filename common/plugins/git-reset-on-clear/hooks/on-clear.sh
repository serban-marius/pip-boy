#!/bin/bash
# Hook: SessionStart (clear)
# Ensures the git repo is on main with the latest code after /clear

cd "$CLAUDE_PROJECT_DIR" || exit 0

# Only act if we're in a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# Stash any uncommitted changes so checkout doesn't fail
has_changes=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  has_changes=true
  git stash push -m "auto-stash before /clear reset" --quiet
fi

git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null || exit 0
git pull --ff-only --quiet 2>/dev/null

# Re-apply stashed changes if any
if [ "$has_changes" = true ]; then
  git stash pop --quiet 2>/dev/null
fi
