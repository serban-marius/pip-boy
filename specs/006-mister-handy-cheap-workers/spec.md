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
| Brief | free-form `Acceptance:` bullet | `Risk: low\|normal\|high` line and an `## Acceptance` section: one command per line, run from the worktree root, exit 0 = accepted, linted (`bash -n`, first word a command); optional `Prod: yes\|no`, `PR: ready\|draft <base>` and `Scope: <globs>` |
| Choosing the agent | always Claude | `bin/route.sh <brief>` prints `<agent> <model> <confidence> <reason>`. Claude opus without asking Jev: no runnable Acceptance, `Risk: high` or missing, `Prod: yes` (without a `Prod:` line, a narrow phrase match for real production writes: deploy/run/migrate … to/on production, prod db/infra/cluster, live customer data; "production code" or "production edit" no longer counts). Then Jev (`jev-latest`, one `choice` question: `nan-flash`, `claude-sonnet`, `claude-opus`, stakes `design`, 10 s timeout); an error, an undecided answer or an empty ladder → `claude sonnet`; confidence under 0.6 → one tier up |
| Implementing | a Claude session | `pi -p -ne --model nan/<id>` in a clean feature-branch worktree, prompted with the brief minus its Reporting section and `PR:` line; no push (`pushurl=/dev/null`, no credential helper), no `gh` (shim, tokens unset); a timeout kills the whole process group; a branch switch or history rewrite is ESCALATE |
| Watching the worker | the worker reports itself | `bin/foreman.sh <slug> <brief> <hq dir> [worktree]`, no LLM: runs the worker, then the Acceptance commands; on failure retries with the failed command and its output appended, climbing the ladder (`MISTER_HANDY_LADDER` or `skills/delegate/ladder`: `nan/deepseek-v4-flash` ×2 → `nan/glm5.3-flash` ×1 → ESCALATE, then HQ relaunches on sonnet, opus only if sonnet fails too); a failed attempt whose pi session ended on the output cap (stopReason `length`) skips that model's remaining tries |
| NAN throttling | n/a | the key allows 7 parallel requests machine-wide and pi gives up after ~3 429s: at most `MISTER_HANDY_NAN_SLOTS` (3) foreman pi runs at once (lock-dir semaphore, dead holders reclaimed, one `waiting for a NAN slot` line); a run that ends on a rate limit is retried after a 60 s doubling backoff without using a ladder try |
| STATUS lines | written by the agent | written by the foreman: START, one MILESTONE per attempt (`attempt n/N <model> PASS\|FAIL '<cmd>' exit <rc>`, never the output), `MILESTONE still working` every 10 min, then DONE `<PR url\|sha on branch>`, `ESCALATE <why>` or FAILED (brief or worktree unfit: no or prose Acceptance, command not found, dirty tree, `main`/`master`/PR base; an Acceptance command that exits 126/127 because it is itself missing or not executable stops at once instead of climbing the ladder) |
| Worker leftovers | n/a | pi always runs with `-ne`; `.atl/` and the `# Local Pi runtime state` / `.atl/` lines extensions add to `.gitignore` are removed (the file restored exactly when nothing else changed), a worker's own `.gitignore` edits kept; build and acceptance artifacts are not committed |
| Commit, push, PR | the agent | files outside `Scope:` fail the attempt; added lines are scanned for secrets (keys, tokens, `.env*`) → ESCALATE with file names, nothing committed; the foreman commits the worker's changes with the brief's title, names changed files the Acceptance runs in DONE, and pushes + opens the PR only with a `PR:` line |
| Cheap model gives up | n/a | `ESCALATE` wakes HQ (watcher), which relaunches the task on Claude sonnet (opus only if asked or sonnet fails too) in the same worktree with `<hq>/logs/<slug>/summary.md` (redacted) and `worker.diff` (new files included); ESCALATE settles the slug until `hq REOPENED` and does not satisfy `after` |
| Review | a Claude reviewer worker | optional `MISTER_HANDY_REVIEW=<nan model>`, which HQ sets for `Risk: normal` briefs: one read-only `pi` pass (`jd-judge-a` prompt, diff against the brief); REVISE items (capped at 4 KB) get one more worker round, kept only if the acceptance still passes, else rolled back with the round's new files removed; no clear verdict is `review inconclusive` |
| Launch | `terminal create --command 'claude ...'` + `send` | Orca: `terminal create --command 'bash <skill dir>/bin/foreman.sh ...'`; subagents: `git worktree add` + background Bash |

HQ skips routing when the user names the agent or model ("hazlo con Claude"), and for
investigations, reviews and preview-driven UI work.

## How we'll know it works

`skills/delegate/bin/delegate.test.sh`, with `pi`, `curl`, `gh` and `orca` stubbed:

- `route.sh` → "production edit"/"production code" stays with Jev, `Prod: yes` → Claude, `Prod: no`
  overrides a deploy phrase; Claude on no Acceptance, a prose Acceptance line, `Risk: high`, no Risk line, a
  production write, a Jev timeout, HTTP error or undecided answer, an empty ladder, one tier up
  under the threshold; `pi <ladder head>` on a confident `nan-flash`, with the ladder head taken
  from `MISTER_HANDY_LADDER`;
- `foreman.sh`: a first-attempt pass is DONE with the commit sha; fail then pass is DONE and the
  retry prompt carries the failure; three failures climb deepseek, deepseek, glm and ESCALATE with the
  work left uncommitted; an output-cap stop skips to the next rung, an older capped session does
  not count for a later attempt, and a cap on the last rung is ESCALATE; `.atl/` and both extension lines in `.gitignore` are removed while a worker's own `.gitignore` edit stays; pi always gets `-ne`; `./missing.sh`, `bash run.sh` with no `run.sh` and a non-executable `./run.sh` stop at once with FAILED after one worker run; build and acceptance
  artifacts are not committed; no Acceptance, a prose Acceptance line, a dirty tree and `main`
  are FAILED with no worker run; files outside `Scope:` fail the attempt and the retry names them;
  a secret or a `.env` file is ESCALATE with nothing committed and no value in STATUS; a pi
  timeout is named and kills the worker's children; a slow attempt writes a heartbeat; the
  worker cannot push or run `gh`; only `PR:` makes the foreman push and open the PR, and the
  worker never sees that line; a branch switch is ESCALATE; a reviewer REVISE gets one more
  round, rolled back when it breaks the acceptance; a `PASSES ...` line does not reset REVISE;
  a silent reviewer is inconclusive;
- `foreman.sh` and NAN limits: a 429 is retried as the same attempt and the slot is released; a busy
  machine waits for a slot and says so once; a dead holder's slot is reclaimed;
- the watcher wakes on `ESCALATE` and the escalated slug settles.

Benchmark: cheap-bench replayed 6 merged pip-boy changes (a one-line hook fix up to a new 37-test
Python module) from their parent commits. Each worker got an HQ-style brief; pass means the merged
commit's hidden test file exits 0. Phase 2 ran route.sh + foreman.sh at `6191e0a`, each task ×2.
Full tables: [`skills/delegate/bench/RESULTS.md`](../../development/common/plugins/mister-handy/skills/delegate/bench/RESULTS.md)
(PR #48).

| strategy | pass (hidden tests) | false DONE | escalated | median wall | NAN tokens per run | Claude $ for the 6 tasks |
|---|---|---|---|---|---|---|
| opus only | 6/6 | 0 | – | 412 s | 0 | $18.96 |
| sonnet only | 6/6 | 0 | – | 91 s | 0 | $1.99 |
| foreman, deepseek ×2 → glm ×1 (the default ladder) | **12/12**, all on attempt 1 | 0 | 0 | **267 s** | 1.1M | $0 |
| foreman, glm ×2 → deepseek ×1 (the previous ladder) | 11/12 | 1 | 0 | 757 s | 762k | $0 |

- Bare pi workers (phase 1, 2 reps per task): deepseek-v4-flash 12/12, glm5.3-flash 9/12 (with or
  without `-ne`; `-ne` removed every stray file), qwen3.8-flash 10/12 at 3.3M tokens, mimo-v2.6-flash 7/12.
- Output cap: glm and mimo end big tasks on stopReason `length`; 11 of 13 retries of the same model
  hit it again. Under the glm-first ladder it ended 4 of the arm's 16 pi sessions, all glm on jira-preview (1717 s
  against 367 s deepseek-first). Hence a cap goes straight to the next rung.
- The glm-first false DONE passed the brief's Acceptance with the hidden tests red. Hence SKILL.md asks
  for the real tests in the Acceptance block, and the cheap reviewer for `Risk: normal`.
- With 0 escalations in 12 runs, the 95 % upper bound on the escalation rate is about 25 %; at that
  rate, relaunching on sonnet still saves about 97 % against opus-only.
- route.sh against Jev was right on 1 of the 6 tasks and over-routed 5 (3 to opus through the
  low-confidence step) where the NAN ladder solved all 6: safe, but it gives up most of the saving.
  Its tiers are unchanged in 1.5.0.

Live: the foreman on a throwaway repo (add `mul()` to `calc.py`, acceptance `python3 test_calc.py`)
with `nan/glm5.3-flash`, the ladder head then, ended in DONE on attempt 1 in ~20 s. With the final ladder,
`nan/deepseek-v4-flash` did the same brief on attempt 1 in 11 s, and the foreman read the session's
last stopReason (`stop`) from pi's session file. `route.sh` against Jev sent that
brief to `pi nan/glm5.3-flash 1.00 jev` and an auth rework across two services to
`claude opus 0.25 low-confidence:claude-sonnet`. After the routing change, the overseer-deno replay
brief (with `Risk: normal` and a runnable Acceptance, its "production edit" wording kept) went to
`pi nan/glm5.3-flash 0.86 jev`; overseer-worktree went to Jev's `claude-sonnet` at 0.46, below the
threshold, so `claude opus`.
