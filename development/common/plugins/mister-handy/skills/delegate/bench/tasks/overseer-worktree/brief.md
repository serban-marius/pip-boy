# overseer-worktree: gate the worktree being edited, not CLAUDE_PROJECT_DIR

## Why
Agents now work in git worktrees of the same repo. overseer's hook starts with
`cd "$CLAUDE_PROJECT_DIR"`, so an agent editing files in a worktree is judged by the main
checkout's spec and per-branch log: it gets "no spec" although its own branch has one, and its red
test runs unlock the wrong branch.

## What we already know
- Plugin: `development/common/plugins/overseer/` (version 0.1.0). Hook: `hooks/overseer.sh`, one
  script for every event (`pre-edit`, `post-edit`, `pre-bash`, `post-bash`, `bash-failed`), reads the
  hook JSON on stdin.
- Edit events carry `tool_input.file_path` (absolute; the file may not exist yet, nor its
  directory). Bash events carry the hook's `cwd` at the top level of the JSON.
- The per-branch log lives in the repo's git dir (`.git/overseer/<branch>.log`, a worktree has its
  own git dir); the off switch is `overseer/off` in the *common* git dir and covers every worktree.
  Both must keep working as they do.
- macOS temp paths are symlinked (`/var` → `/private/var`): `git rev-parse --show-toplevel` returns
  the resolved path, which then no longer matches `file_path`. Reaching the top level through
  `git rev-parse --show-cdup` keeps the path the caller used.
- Tests: `bash development/common/plugins/overseer/hooks/overseer.test.sh` (needs `jq`).

## Task
- Decide which repo to gate from the event itself: for an edit, the repo containing
  `tool_input.file_path` (walk up to the nearest existing directory); for a Bash event, the repo at
  the input's `cwd`; only when neither gives a directory, fall back to `CLAUDE_PROJECT_DIR`. Outside
  any git repo, exit 0 as today.
- Then work from that repo's top level so spec lookup, log and branch are that worktree's.
- Bump overseer to 0.1.1 in its `plugin.json` and in `.claude-plugin/marketplace.json`.

## Acceptance
- With the main checkout on one branch and a second worktree on another branch that has its own
  spec (`openspec/changes/<name>/proposal.md` or `specs/...`): a production edit in the worktree
  gets "red first" (its spec is found), not "no spec"; a test-file edit plus a failing test run
  with `cwd` = the worktree unlocks production edits in that worktree only; the main checkout
  keeps its own gate ("no spec").
- Cover it in `overseer.test.sh`; the whole file is green, existing cases included.
- Commit message in the repo's style, e.g. `fix(overseer): ... (0.1.1)`.
