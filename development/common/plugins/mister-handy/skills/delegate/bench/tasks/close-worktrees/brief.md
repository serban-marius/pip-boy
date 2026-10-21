# close-worktrees: mister-handy closes worktrees when their work is over (1.3.0)

## Why
One HQ session ran ~10 Orca workers for a day. It worked, with three gaps:
- Workers with nothing left to do kept their worktree and agent terminal open until someone asked
  for a cleanup: no-code tasks (reviewer, e2e run, credentials setup) from the moment they wrote
  DONE, PR tasks from the moment their PR merged outside the session. Removing them needed
  `orca worktree rm --force` whenever the local branch had no upstream, even with nothing unique
  in it.
- A worker that finished a follow-up wrote `DONE PR #7 description simplified` while its main job
  went on; the watcher counted the task as over and printed `ALL-SETTLED` with that worker busy.
- A worker wrote `MILESTONE tsnet ready` meaning "HQ, give the other worker the go". MILESTONE does
  not wake HQ, so the hand-off waited ~5 minutes until the user asked.

## What we already know
- Plugin: `development/common/plugins/mister-handy/` (1.2.0), skill `skills/delegate/`:
  `SKILL.md` (HQ's playbook, including the brief template workers get and the watcher's event
  table) and `bin/watch.sh <hq dir> [quiet minutes]`, which blocks on `_hq/STATUS.md` (lines
  `HH:MM <slug> <STATE> <text>`; HQ's own lines are `HH:MM hq <VERB> <slug> ...`), prints what HQ
  must act on, remembers its read offset in `<hq>/.watch-offset` and exits. Read it first.
- There are no tests for `bin/` yet.
- `gh pr view <url> --json state -q .state` prints `OPEN`, `MERGED` or `CLOSED`.
  `gh pr list --head <branch> --state merged --json headRefOid -q '.[].headRefOid'` prints the head
  sha of each merged PR from that branch, one per line.

## Task
1. `specs/004-mister-handy-close-worktrees/spec.md` (Why / What changes / How we'll know).
2. New `skills/delegate/bin/closable.sh <worktree path>`: proves a worktree holds nothing unique.
   - Prints exactly `CLOSABLE` (exit 0) when the working tree is clean and every commit is on some
     remote branch, or the unpushed HEAD is the head of a merged PR of its branch (`gh`, above).
   - Otherwise prints `KEEP <why>` (exit 1), with `<why>` exactly `uncommitted changes`,
     `commits on no remote branch and no merged PR with this head`, or both joined by `; `.
   - Works with no upstream configured. Not a git dir → `KEEP not a git worktree: <path>`.
3. `watch.sh`:
   - New wake states: `HANDOFF` and `DONE-STEP` lines are printed and end the wait like the other
     event lines (ANSWER, BLOCKED, DONE, FAILED, REVISED).
   - `DONE-STEP` (a follow-up finished while the main job goes on) does **not** settle the slug: it
     stays live, so a later quiet period still lists it (`QUIET <min>m <slugs>` format unchanged,
     slugs each followed by a space).
   - A `DONE` line carrying a GitHub PR URL (`https://github.com/<o>/<r>/pull/<n>`) leaves the slug
     waiting for its merge: the watcher polls `gh pr view <url> --json state -q .state` on its first
     tick and every 5 minutes after, and when the PR is merged or closed prints
     `PR-MERGED <slug> <url>` or `PR-CLOSED <slug> <url>` and exits. While it is open nothing is
     printed. HQ's `hq CLOSED <slug>`, `hq KEPT <slug> <why>` or `hq REOPENED <slug>` ends the wait.
   - `ALL-SETTLED` only when no slug is live **and** none is waiting for a merge. A `DONE` without a
     PR URL (a `no-code` task) settles as today.
   - Update the header comment listing exit lines.
4. `SKILL.md`: default `on-done` becomes `close` (a no-code task at its DONE, a PR task once its PR
   is merged or closed; `keep` for workers HQ will send more work to); before
   `orca worktree rm --force` HQ runs `closable.sh` and only removes on `CLOSABLE`, then appends
   `hq CLOSED <slug>` (or `hq KEPT <slug> <why>`); the brief template asks workers for the full PR
   URL in DONE, `DONE-STEP` for follow-ups and `HANDOFF <to-slug> <what>` for chained work; the
   event table gets rows for `DONE-STEP`, `HANDOFF`, `PR-MERGED`/`PR-CLOSED`. README in step.
5. Bump mister-handy to 1.3.0 in its `plugin.json` and `.claude-plugin/marketplace.json`.

## Acceptance
- New `skills/delegate/bin/delegate.test.sh` (bash, `gh` stubbed on PATH, temp dirs, a bare repo
  as remote; prints `ok   <name>` / `FAIL <name>` per case and exits non-zero on any failure)
  covering: DONE-STEP and HANDOFF wake and are printed; after DONE-STEP the slug is still live; a
  no-code DONE settles to `ALL-SETTLED`; a DONE with a PR URL does not settle while the PR is open,
  prints `PR-MERGED`/`PR-CLOSED` once it ends, and settles after `hq CLOSED` / `hq KEPT`;
  `closable.sh`: clean and pushed → `CLOSABLE`, uncommitted or unpushed → `KEEP ...`, unpushed but
  the head of a merged PR → `CLOSABLE`. Green.
- Commit message in the repo's style, e.g. `feat(mister-handy): ... (1.3.0)`.
