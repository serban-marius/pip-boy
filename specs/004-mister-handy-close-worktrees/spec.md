# 004 · mister-handy closes worktrees when their work is over

## Why

One HQ session ran ~10 Orca workers for a day. It worked, with three gaps:

- Workers with nothing left to do kept their worktree and agent terminal open until someone asked
  for a cleanup: no-code tasks (reviewer, integration or e2e run, credentials setup) from the
  moment they wrote DONE, PR tasks from the moment their PR merged outside the session. Removing
  them needed `orca worktree rm --force` whenever the local branch had no upstream, even with
  nothing unique in it.
- A worker that finished a follow-up wrote `DONE PR #7 description simplified` while its main job
  went on; the watcher counted the task as over and printed `ALL-SETTLED` with that worker busy.
- A worker wrote `MILESTONE tsnet ready` meaning "HQ, give the other worker the go". MILESTONE
  does not wake HQ, so the hand-off waited ~5 minutes until the user asked.

## What changes

| Case | Today | After |
|---|---|---|
| Default `on-done` | `report` | `close`: a `no-code` task at its DONE, a PR task once its PR is merged or closed; `keep` for workers HQ will send more work to |
| Proving a worktree holds nothing unique | `git log @{u}..`, fails with no upstream | `bin/closable.sh <path>`: `CLOSABLE` when the tree is clean and every commit is on a remote branch or is the head of a merged PR; `KEEP <why>` otherwise. Only then `orca worktree rm --force` |
| A DONE line with a PR URL | settles the task | the watcher polls the PR (first tick, then every 5 min) and prints `PR-MERGED <slug> <url>` or `PR-CLOSED <slug> <url>`; HQ closes the worktree and appends `hq CLOSED <slug>`, or `hq KEPT <slug> <why>` |
| `ALL-SETTLED` | every task DONE, FAILED or CLOSED | also nothing waiting for a merge |
| A follow-up finished while the main job goes on | `DONE`, settles the task | `DONE-STEP`, wakes HQ, the task stays live |
| A worker needs HQ to pass something to another worker | `MILESTONE`, no wake | `HANDOFF <to-slug> <what>`, wakes HQ, which forwards it without asking the user |

The brief asks for the full PR URL in DONE (HQ may run outside any repo), `DONE-STEP` for
follow-ups and `HANDOFF` for chained work; follow-up messages to a busy worker say the same.

## How we'll know it works

`skills/delegate/bin/delegate.test.sh`, with `gh` stubbed:

- `DONE-STEP` and `HANDOFF` lines are printed; after `DONE-STEP` the slug is still live (`QUIET`);
- a `no-code` DONE settles; a DONE with a PR URL does not while the PR is open, prints
  `PR-MERGED` once it is merged, and settles after `hq CLOSED` or `hq KEPT`;
- `closable.sh`: clean and pushed → `CLOSABLE`; uncommitted or unpushed → `KEEP`; unpushed but
  the head of a merged PR → `CLOSABLE`.
