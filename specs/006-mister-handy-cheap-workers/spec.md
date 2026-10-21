# 006 · mister-handy cheap workers: Jev routes, pi implements, a foreman watches

## Why

Every delegated task ran on Claude, so the Claude quota paid for typing as well as thinking. The
user also has a NAN Builders quota (open-source models through the `pi` CLI) and wants Claude to
keep only the deciding: "que Claude solo se quede en la parte de decidir qué hacer y cómo hacerlo
y que la implementación la hagan agentes que usen LLM mucho más baratos", with the agent for each
task picked "mediante Jev o similar".

A small model cannot be trusted to judge its own result or to keep the STATUS protocol, so the
decision of "done" moves to commands the brief carries, and the reporting moves to a script.

## What changes

| Case | Today | After |
|---|---|---|
| Brief | free-form `Acceptance:` bullet | `Risk: low\|normal\|high` line and an `## Acceptance` section: one command per line, run from the worktree root, exit 0 = accepted; optional `PR: ready\|draft <base>` |
| Choosing the agent | always Claude | `bin/route.sh <brief>` prints `<agent> <model> <confidence> <reason>`. Claude without asking Jev: no Acceptance, `Risk: high` or missing, a non-negated prod/production line. Then Jev (`jev-latest`, one `choice` question: `nan-flash`, `claude-sonnet`, `claude-opus`, stakes `design`, 10 s timeout); an error or an undecided answer → `claude opus`; confidence under 0.6 → one tier up |
| Implementing | a Claude session | `pi -p -ne --model nan/<id>` in the worktree, prompted with the brief minus its Reporting section |
| Watching the worker | the worker reports itself | `bin/foreman.sh <slug> <brief> <hq dir> [worktree]`, no LLM: runs the worker, then the Acceptance commands; on failure retries with the failed command and its output appended, climbing the ladder (`MISTER_HANDY_LADDER` or `skills/delegate/ladder`, placeholder `nan/glm5.3-flash` ×2 → `nan/deepseek-v4-flash` ×1) |
| STATUS lines | written by the agent | written by the foreman: START, one MILESTONE per attempt (`attempt n/N <model> PASS\|FAIL ...`), then DONE `<PR url\|sha on branch>`, `ESCALATE <why>` or FAILED (broken setup only) |
| Worker leftovers | n/a | `.atl/` and its `.gitignore` line removed when they were not there before; build and acceptance artifacts are not committed |
| Commit, push, PR | the agent | the foreman commits the worker's changes with the brief's title; pushes and opens the PR only with a `PR:` line |
| Cheap model gives up | n/a | `ESCALATE` wakes HQ (watcher), which relaunches the task on Claude in the same worktree with `<hq>/logs/<slug>/summary.md`; ESCALATE settles the slug until `hq REOPENED` |
| Review | a Claude reviewer worker | optional `MISTER_HANDY_REVIEW=<nan model>`: one read-only `pi` pass (`jd-judge-a` prompt, diff against the brief); REVISE items get one more worker round, kept only if the acceptance still passes |
| Launch | `terminal create --command 'claude ...'` + `send` | Orca: `terminal create --command 'bash <skill dir>/bin/foreman.sh ...'`; subagents: `git worktree add` + background Bash |

HQ skips routing when the user names the agent or model ("hazlo con Claude"), and for
investigations, reviews and preview-driven UI work.

## How we'll know it works

`skills/delegate/bin/delegate.test.sh`, with `pi`, `curl`, `gh` and `orca` stubbed:

- `route.sh` → Claude on no Acceptance, `Risk: high`, no Risk line, a production write, a Jev
  timeout, HTTP error or undecided answer, one tier up under the threshold; `pi <ladder head>` on
  a confident `nan-flash`, with the ladder head taken from `MISTER_HANDY_LADDER`;
- `foreman.sh`: a first-attempt pass is DONE with the commit sha; fail then pass is DONE and the
  retry prompt carries the failure; three failures climb glm, glm, deepseek and ESCALATE with the
  work left uncommitted; `.atl/` and its `.gitignore` line are removed; build and acceptance
  artifacts are not committed; no Acceptance is FAILED; a reviewer REVISE gets one more round;
- the watcher wakes on `ESCALATE` and the escalated slug settles.

Live: the foreman on a throwaway repo (add `mul()` to `calc.py`, acceptance `python3 test_calc.py`)
with `nan/glm5.3-flash` ended in DONE on attempt 1 in ~20 s. `route.sh` against Jev sent that
brief to `pi nan/glm5.3-flash 1.00 jev` and an auth rework across two services to
`claude opus 0.25 low-confidence:claude-sonnet`.
