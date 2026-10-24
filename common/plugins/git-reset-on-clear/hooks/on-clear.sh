#!/bin/bash

export GIT_TERMINAL_PROMPT=0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" 2>/dev/null || exit 0

default_branch() {
  local candidate
  candidate=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  candidate=${candidate#origin/}
  if [ -n "$candidate" ] && git show-ref --verify --quiet "refs/heads/$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  echo "git-reset-on-clear: working tree has changes; left it alone"
  exit 0
fi

git_dir=$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)
common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
if [ "$git_dir" != "$common_dir" ]; then
  echo "git-reset-on-clear: linked worktree; left it alone"
  exit 0
fi

current=$(git symbolic-ref -q --short HEAD 2>/dev/null)
if [ -z "$current" ]; then
  echo "git-reset-on-clear: detached HEAD; left it alone"
  exit 0
fi

target=$(default_branch)
if [ -z "$target" ]; then
  echo "git-reset-on-clear: no default branch; left it alone"
  exit 0
fi

if [ "$current" != "$target" ]; then
  if git checkout --quiet "$target" 2>/dev/null; then
    echo "git-reset-on-clear: switched $current -> $target"
  else
    echo "git-reset-on-clear: could not switch $current -> $target"
  fi
  exit 0
fi

if git pull --ff-only --quiet 2>/dev/null; then
  echo "git-reset-on-clear: pulled $target"
else
  echo "git-reset-on-clear: could not fast-forward $target"
fi
exit 0
