---
name: delegate
description: "Keep this session as HQ: send substantive work (investigations, fixes, features, PRs, reviews) out as written briefs, one agent each, to Orca worktrees when running in Orca or to background Claude Code subagents in their own git worktrees otherwise, instead of doing it here; briefs with runnable Acceptance commands are routed by Jev and, when a cheap model fits, implemented by `pi` on NAN models under a deterministic foreman that retries, climbs a model ladder and escalates to Claude; HQ then watches them in the background and acts when they finish, fail, ask or go quiet (review, merge on standing orders, launch chained tasks, close worktrees); workers report through a STATUS file (and their Orca card), never by messaging this session; then answer 'how is it going', pass follow-ups and approvals to a worker, and clean up finished worktrees, all without pulling transcripts back into this context. Use when the user says 'open/spool/boot/spin up an orca worktree for this', 'launch some orca worktrees', 'lanza un orca worktree', 'lánzate unos worktrees y a currar', 'monta unos worktrees', 'hazlo en otro worktree', 'give the task to the X orca session', 'mándaselo a la sesión del worktree', 'quédate vigilándolos', 'ves chapando worktrees si han terminado', 'do a cleanup of worktrees', 'close the worktree if we're done', 'bring the summary here', 'keep this session clean', 'hazlo con un modelo barato', 'hazlo con pi', 'hazlo con Claude', or '/delegate'. Also the DEFAULT for any substantive task, worded or not, whenever the mister-handy SessionStart note says this session is HQ."
---

# Delegate to worktrees, keep HQ clean

This session is HQ, and it orchestrates: it launches workers, watches them, and acts when they
finish or get stuck. Its context is for what the user cares about: decisions, briefs, short
status, approvals. The digging, the diffs, the test runs and the PR babysitting happen in
worktrees, each with its own agent. Everything in this skill serves one rule:

**Nothing a worker does should land in this context unless the user asks for it.**

So workers never message HQ. They append one-line updates to a STATUS file (and, in Orca, set
their card comment); HQ reads those files when the user asks. (Supervised `orca orchestration`
runs break this rule: every worker message is injected here as "You have 1 orchestration
message. Run `orca orchestration check`…", dozens of times per run. Do not use
`orchestration worker-start`, `dispatch`, `send` or `check --wait` from this skill.)

## When this runs, and which backend

The plugin's SessionStart hook prints one note per session: HQ (on the repo's default branch,
or outside any repo) or worker (any other branch). In an HQ session this skill is the default
for every substantive task; the user does not have to say "worktree". In a worker session never
use it: do the work. The user can always say "hazlo aquí" to keep one task in HQ.

Backend, also named in that note:

- **orca** (running inside Orca): Orca worktrees, one agent per worktree. Modes 1-5 below.
- **subagents** (plain Claude Code): background subagents, each in its own git worktree when it
  edits files. Same briefs, same STATUS protocol; see "Without Orca" for what changes.

## What stays here and what goes out

Goes out: anything that needs more than a few reads to answer, any code change, anything that
ends in a PR or a report, any review, anything long-running (deploy watches, simulations).

Stays here: reading just enough to write a good brief (the ticket, the user's words, the paths
they mentioned), answering from what is already in context, and the status, follow-up and
cleanup modes below. Do not start the investigation "to save the worker time"; that is the
context this skill exists to protect.

## HQ files

One folder per repo, next to its worktrees, outside every git checkout:

```
<workspaces>/<repo>/_hq/
  briefs/<slug>.md     one brief per task (the worker's whole world)
  assets/<slug>/       screenshots and files the brief points at
  reports/<slug>.md    long findings, when a task asks for a written report
  reviews/<slug>.md    reviewer verdicts
  STATUS.md            append-only, one line per event, all workers
  SESSIONS.md          slug, worktree path, terminal handle, agent, started, on-done, after
```

With the subagents backend there is no workspaces folder: use `~/.claude/hq/<repo name>/`
(or `~/.claude/hq/_global/` outside a repo) with the same layout.

Find `<workspaces>/<repo>` as the parent of the HQ session's own worktree
(`orca worktree current --json` → `result.worktree.path`). If HQ is not inside a worktree of
the target repo, take the parent of any path in `orca worktree list --repo <selector> --json`.
Create `_hq/` on first use, with `STATUS.md` starting `# append-only: HH:MM <slug> <STATE> <text>`.

## Mode 1: delegate one task

1. **Name it.** A short kebab slug for the task (`bench-baseline`, `ds-3863-aurora-reviews`).
   Use the ticket key when there is one. Check `SESSIONS.md` and `orca worktree list` so it
   is unique.
2. **Check the base.** Find the integration branch: the base recent PRs merged into
   (`gh pr list --state merged --limit 20 --json baseRefName -q '.[].baseRefName' | sort | uniq -c`),
   else the repo's docs (`dev`, `develop`, `staging`), else the default branch. When the work
   would build on another branch (stacked work, "branch from X"), `git fetch` and check it
   against the integration branch: `git cherry origin/<integration> origin/<candidate>` (`-`
   lines are already in under another sha) and
   `git rev-list --left-right --count origin/<integration>...origin/<candidate>`. Nothing left
   to bring (no `+` lines) or far behind → base on the integration branch; a mix → ask the user.
   The brief names the base and the PR target.
3. **Write the brief** to `_hq/briefs/<slug>.md`. It must stand on its own: the worker has
   none of this conversation. Use this shape:

   ```markdown
   # <slug>: <one-line goal>
   Risk: <low|normal|high>
   Prod: <yes|no>                  (yes = writes to production: deploys, prod DBs or infra, live customer data)
   PR: <ready|draft> <base>        (optional; only for cheap workers, see "Cheap workers")
   Scope: <globs>                  (optional; files a cheap worker may change)

   ## Why
   What the user wants and why, in their terms. Quote their words when they are precise.

   ## What we already know
   Facts HQ has (ticket key and link, PR numbers, paths with line numbers, prior findings,
   decisions the user already made). Mark guesses as guesses.

   ## Task
   - Target: files, service, environment in scope.
   - Change: the concrete result (a fix, a PR, a report answering questions 1..n).
   - Constraints: what must not change; read-only or not; prod rules.
   - Ownership: what this worker may edit. Other workers own <...>; do not touch them.
   - Evidence: anything the Acceptance commands cannot prove (screenshots, a report).

   ## Acceptance
   <one shell command per line, run from the worktree root; every one exits 0 = accepted>

   ## Rules
   - You are on a fresh branch from `<base>`; rename it to the repo's branch convention if it
     has one, and follow its commit conventions.
   - <PR: open it with `--base <base>` / local commits only / ready-for-review or draft>.
     Never push to main.
   - <UI task> Within ~20 min of starting, have a preview running and write
     `ANSWER PREVIEW <url> <login>`; keep it showing your current work. Before implementing a
     design change, put the punch list with screenshots in <abs path>/_hq/reports/<slug>.md and
     write `ANSWER PUNCH-LIST <path>`; carry on with the clear fixes, BLOCKED on judgement calls.
   - "Before" screenshots come from `<base>` in another checkout or the deployed app, never from
     reverting your working tree: the preview must always show your work.
   - Secrets: read <VAR> from <path>; never print or copy secret values.
   - Never bare `git stash`.

   ## Reporting (the only channel back to HQ)
   - Append lines to <abs path>/_hq/STATUS.md: `HH:MM <slug> <STATE> <text>`, STATE one of
     START, MILESTONE, ANSWER, BLOCKED, HANDOFF, HANDOFF-FYI, REVISED, DONE-STEP, DONE, FAILED
     (gave up, with why).
   - DONE means the whole task is over, and carries the full PR URL
     (`https://github.com/<owner>/<repo>/pull/<n>`), a commit sha or `no-code`, plus the report
     path if any. A follow-up from HQ finished while the main job goes on is `DONE-STEP`.
   - Another worker needs something from you (a go, a URL, a service up): write
     `HANDOFF <their slug> <what>`; HQ forwards it. Information they need no action on:
     `HANDOFF-FYI <their slug> <what>` (it does not wake HQ).
   - Lines for you: before each MILESTONE or DONE, and when you start the next piece, run
     `awk '$2 != "<slug>" && / <slug>([: ]|$)/' <abs path>/_hq/STATUS.md` and act on the new
     ones (`HANDOFF <slug>`, `hq ... <slug>`). Do not wait for HQ to forward them.
   - Keep your Orca card current: `orca worktree set --worktree active --comment "<state>" --json`.
   - Blocked on a human decision: write a BLOCKED line with the exact question, run
     `orca worktree set --worktree active --unread --json`, and wait in your own terminal.
   - Never message, `terminal send` to, or `orchestration send` to the session that launched you.
   - Long findings go to <abs path>/_hq/reports/<slug>.md, not into STATUS.
   ```

   Time-critical work: ask for an early `ANSWER` line ("within 15 min") before the full job.
4. **Images and drops.** A worker cannot see `[Image #N]` or HQ's attachments, and Orca drop
   paths under `/var/folders/.../orca-drop-*` are temporary. Copy every file the task needs
   into `_hq/assets/<slug>/` and, for pasted images, describe in the brief what they show.
5. **Route, then launch.** Run `bash <skill dir>/bin/route.sh <brief>` first ("Cheap workers"
   below): `pi <model> ...` → launch the foreman there instead of the rest of this step;
   `claude <sonnet|opus> ...` → go on here with `--model <sonnet|opus>`. Launch the agent in a terminal, never with `--agent`: that follows the user's Chat UI
   setting and may start a chat session, which has no terminal handle, so HQ could never send
   it a follow-up, an approval or a hand-off (Mode 4).

   ```text
   orca worktree create --repo <selector> --name <slug> --no-parent --comment "starting" --json
   orca terminal create --worktree id:<full worktree id> --title <slug> --command 'claude --permission-mode auto' --json
   orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
   orca terminal send --terminal <handle> --text "Your task brief is in <abs brief path>. Read it, work autonomously until DONE, and report only as it says (STATUS.md lines and your Orca card). Never message the session that launched you." --enter --wait-submit 10 --json
   ```

   - Add `--base-branch <base>` when the base check picked anything but the repo default. Use
     `--parent-worktree active` only when the user asks for stacked work.
   - `--permission-mode auto` keeps a worker in its isolated worktree from stalling on prompts
     (`acceptEdits` still stops at every shell command); the user's own choice wins. Add
     `--model <model> --effort <level>` when the user names them; another agent (`codex`,
     `pi`, ...) goes in `--command` the same way.
   - The launch counts only when `terminal create` returned a `term_...` handle, the wait
     reported `satisfied: true` (retry once with a longer timeout) and the send `accepted: true`.
     Otherwise stop: tell the user the task did not start and why, and record nothing.
   - If the bare create opened a fallback shell, close it only after `orca terminal show`
     confirms it is an unused shell.
6. **Record** a line in `SESSIONS.md`
   (`<slug>  <worktree path>  <term handle>  <agent>  <HH:MM>  on-done: <order>  after: <slug|->`)
   and append `HH:MM hq DISPATCHED <slug>` to `STATUS.md`. `on-done` is the user's standing
   order for when it finishes ("review it", "merge if green"), and ends in closing the worktree
   (Mode 5) unless it says `keep`. Default `close`: a `no-code` task closes at its DONE, a PR
   task once its PR is merged or closed. Use `keep` for workers HQ will send more work to.
   `after` names a task this one waits for (Mode 2 chains); such a task is recorded but not
   launched yet.
7. **Report and watch.** One line to the user: slug, worktree, what it will deliver. Then arm the
   watcher (Mode 6) if it is not already running, and end the turn. Never sit waiting in a
   foreground command.

### Another host ("en la raspberry")

Find the paired server with `orca environment list --json` and create there with
`--project <projectId> --host runtime:<environment id>` (the project must already have a host
setup there: `orca project setups --json`), then launch as in step 5 with
`--environment <environment id>` on the terminal commands. HQ files are not reachable from
that host, so the send carries the whole brief, and the worker reports through its Orca card
comment and its PR only; `orca worktree ps --json` shows remote cards. For anything beyond
this, read `orca skills get orca-cli --reference references/placement-and-remote.md`.

## Cheap workers

Claude decides what to do and how; the implementation goes to a much cheaper open-source model
when the brief can prove its own result. Three pieces, none of them spends Claude tokens:

- **Router** `bin/route.sh <brief>` asks Jev (`api.typesafe.ai`, key in `TYPESAFE_API_KEY` or
  the keychain item `jev`) which tier fits and prints one line `<agent> <model> <confidence> <reason>`.
- **Worker** `pi` on a NAN model (`nan/*`), headless, in its own worktree, with the same brief.
- **Foreman** `bin/foreman.sh`, a plain script: runs the worker, then the brief's Acceptance
  commands; on failure gives the worker the output and retries, climbing the ladder; writes the
  STATUS lines itself, so the protocol does not depend on the small model's discipline.

**The brief** needs a `Risk:` line and an `## Acceptance` section: one command per line, run from
the worktree root, every one exits 0 = accepted. Write commands a stranger could run: tests that
exist, or a test file the brief spells out. The worker sees them; weak checks let weak work through.
The Acceptance block must hold the real tests for the change, the ones a reviewer would run, not a
smoke check (`bash -n`, `--help`, one happy-path call): the foreman's DONE means only that these
commands passed. In the benchmark (`bench/RESULTS.md`), glm5.3-flash reached DONE on a passing
Acceptance while the hidden tests were red; Claude and deepseek under the foreman never did.
`PR: ready <base>` (or `draft`) makes the foreman push and open the PR after a pass; without it
the work stays as a local commit. `Scope: <globs>` (space-separated, e.g. `src/calc/* tests/test_calc.py`)
fails any attempt that changes a file outside them. Acceptance lines that are prose or not valid
shell are refused before any worker runs. Say `Prod: yes` for real production writes (deploys,
prod DBs or infra, live customer data) and `Prod: no` otherwise; editing a repo's production
source is ordinary work. Without the line the router falls back to a narrow phrase match, so the
explicit line, and `Risk: high` for anything touching shared or live systems, are the real gates.

**Routing** (`route.sh`):

| Brief | Output |
|-------|--------|
| No Acceptance commands, or a line that is not a runnable command | `claude opus 1.00 no-acceptance` / `acceptance-not-runnable` |
| `Risk: high`, or no `Risk:` line | `claude opus 1.00 risk-high` / `no-risk` |
| `Prod: yes`; without a `Prod:` line, a phrase like "deploy to prod", "run … on production", "prod db/infra/cluster", "live customer data" with no negation | `claude opus 1.00 production` |
| Jev missing key, timeout, HTTP error, unknown answer; an empty ladder | `claude sonnet 0.00 jev-<why>` / `empty-ladder` |
| Jev answer under `MISTER_HANDY_ROUTE_THRESHOLD` (0.6) | one tier up: `claude sonnet 0.41 low-confidence:nan-flash` |
| Jev `nan-flash` / `claude-sonnet` / `claude-opus` | `pi <ladder head> 0.83 jev` / `claude sonnet ...` / `claude opus ...` |

Skip routing and launch Claude when the user names the agent or model ("hazlo con Claude", "con
opus"; "con pi" forces the foreman), and for investigations, reviews and UI tasks that need a
preview: they end in judgement, not in a command that exits 0.

**Launching the foreman.** Orca: create the worktree as in Mode 1 step 5, then run the foreman
itself as the terminal command, so the card shows it; no `wait` or `send`:

```text
orca terminal create --worktree id:<full worktree id> --title <slug> --command 'bash <skill dir>/bin/foreman.sh <slug> <abs brief path> <abs path>/_hq' --json
```

Subagents: `git worktree add -b <branch> <repo>/.claude/worktrees/<slug> origin/<base>`, then the
Bash tool with `run_in_background: true`:
`bash <skill dir>/bin/foreman.sh <slug> <brief> <hq dir> <worktree path>`.
Record `foreman <ladder head>` as the agent in `SESSIONS.md`. The foreman starts only on a clean
feature branch (not `main`, `master` or the `PR:` base); anything else is `FAILED`.

For `Risk: normal` briefs, add the cheap reviewer: prefix the command with
`MISTER_HANDY_REVIEW=nan/glm5.3-flash` (a model other than the ladder head), so a second model
reads the diff against the brief before DONE. `Risk: low` briefs can skip it.

**What the foreman does**, per attempt of the ladder (`MISTER_HANDY_LADDER="nan/deepseek-v4-flash 2,nan/glm5.3-flash 1"`,
else the `ladder` file next to this skill, `<model> <tries>` per line; deepseek first passed 12/12
benchmark runs on the first attempt, glm first 11/12 and about 3× slower):

1. `pi -p -ne --model <model>` with the brief minus its Reporting section and `PR:` line; from
   the second attempt on, with the failed command and its output appended. The tree keeps the
   previous attempt's changes. The worker cannot push (`remote.origin.pushurl=/dev/null`, no
   credential helper) or use `gh` (a failing shim, tokens unset); a worker that switches branch
   or rewrites history is `ESCALATE`. A timeout kills its whole process group. Every 10 min of an
   attempt the foreman writes `MILESTONE still working: ...`, so `QUIET` stays for real stalls.
2. pi always runs with `-ne` (`MISTER_HANDY_PI_FLAGS` only adds flags). If `.atl/` or the
   `# Local Pi runtime state` / `.atl/` lines that pi extensions write into `.gitignore` still
   appear, they are removed (`.gitignore` restored byte for byte when that was all that changed).
3. Checks `Scope:`, then runs the Acceptance commands, stops at the first failure; one
   `MILESTONE attempt n/N <model> PASS|FAIL '<command>' exit <rc> (<s>s[, pi timed out])` line,
   never the command's output (that stays in the logs, and redacted in `summary.md`). Logs
   (prompt, pi output, pi sessions, acceptance output, `summary.md`) go to `<hq>/logs/<slug>/`,
   outside the repo. A failed attempt whose pi session ended on the model's output cap (stopReason
   `length`) skips that model's remaining tries (`, output cap: no more <model> tries`): retrying the same model
   hit the cap again 11 times out of 13 in the benchmark.
4. Pass → scans the added lines for secrets (private keys, `sk-`, `AKIA`, `gh*_` tokens,
   `api_key|token|secret|password = <long value>`, `.env*` files): a hit is `ESCALATE` with the
   file names, nothing committed. Otherwise commits what the worker changed (not build or acceptance
   artifacts) with the brief's title, pushes and opens the PR when the brief has `PR:`, and writes
   `DONE <PR url|sha on branch>`, naming any changed file the Acceptance commands run (a test the
   worker edited deserves a look). Last attempt failed → `ESCALATE <why>`, changes left
   uncommitted, diff including new files in `worker.diff`. `FAILED` for a brief or worktree that
   is not fit to start (no Acceptance, prose in it, a command not found, dirty tree, wrong branch),
   and at once, without climbing the ladder, when an Acceptance command exits 126/127 because the
   command itself (`./run.sh`, `bash run.sh`, a bare name) is missing or not executable.

`MISTER_HANDY_REVIEW=<nan model>` adds one read-only reviewer pass after a pass (pi with read
tools only, `jd-judge-a` prompt, the diff against the brief): REVISE items get one more worker
round, kept only if the acceptance still passes (otherwise rolled back, with the round's new files
removed). A reviewer with no clear verdict is noted as `review inconclusive`, never as PASS. Timeouts: `MISTER_HANDY_PI_TIMEOUT` (1800 s per
attempt), `MISTER_HANDY_CHECK_TIMEOUT` (600 s per command).

The NAN key allows 7 parallel requests for every pi on the machine, and pi gives up after a few
429s. So the foreman runs at most `MISTER_HANDY_NAN_SLOTS` (3) pi processes at once per user (a
lock-dir semaphore in `~/.cache/mister-handy/nan-slots`, a dead holder's slot reclaimed), writing
`MILESTONE waiting for a NAN slot` once while it waits. A pi run that ends on a rate limit is
retried after a backoff (`MISTER_HANDY_RATE_BACKOFF` 60 s, doubling to 600 s, up to
`MISTER_HANDY_RATE_RETRIES` 5 times) with `MILESTONE ... rate-limited, retry n`, and does not use
up a ladder try.

**When the watcher wakes HQ:**

- `DONE` with a PR URL: as any DONE. `DONE <sha> on <branch> (local)`: not `no-code`; look at
  `git -C <worktree> diff --stat <base>...` and push + open the PR yourself, or launch a reviewer.
- `ESCALATE`: relaunch on Claude in the same worktree, as Mode 1 step 5 with
  `--worktree path:<worktree>` and `--model sonnet`: one tier up from the cheap one, as the router
  does; `opus` only when the user asks or a sonnet relaunch also fails. Send: "Your task brief is
  in <brief>. A cheap worker tried it first and failed: read <hq>/logs/<slug>/summary.md and
  `git status --short`, keep or discard its uncommitted changes, then work until DONE and report
  as the brief says." Update `SESSIONS.md` and append `hq REOPENED <slug>`. ESCALATE does not
  satisfy `after`: tasks waiting on this slug wait for the relaunch's DONE. A secret or
  branch ESCALATE: look at the named files or branch first; tell the user before relaunching.
  Subagents: one background Agent with that prompt, told to work in that worktree path.
- `FAILED` from the foreman: fix the brief and relaunch it, or launch Claude.

## Mode 2: fan out ("lánzate unos worktrees")

1. Split by what the user will see, not by files: the slice they can look at goes first and
   gets the first preview checkpoint; backend and plumbing slices feed it. Then split into
   tasks that can run at the same time. **Give every file one owner.**
   Two workers editing the same files end in conflicting PRs; merge such tasks into one worker
   or chain them: write both briefs, launch the first, record the second with `after: <first>`;
   the watcher launches it when the first is DONE and merged. When a worker must signal another
   mid-task (a go, a URL, a service up), its brief says to write a `HANDOFF` line for it
   (`HANDOFF-FYI` when no action is needed).
2. Tell the user the split in one line per task, then go without waiting for approval unless a
   task writes to production or the split is a real judgement call.
3. Write all briefs, then launch all worktrees in one message (parallel tool calls). Each brief
   names the other workers and what they own.
4. Report the table (slug, delivers, worktree, on-done) and arm the watcher (Mode 6).

## Mode 3: status ("¿cómo va?", "bring the summary here")

Read, in this order, and stop as soon as the question is answered:

1. `tail -n 40 _hq/STATUS.md`
2. `orca worktree ps --json` (cards, comments, unread flags, across hosts)
3. `gh pr list --head <branch> --state all` or `gh pr view <n>` for workers that reported a PR

Answer with one row per task: slug, state, last line, PR, and what needs the user (every
BLOCKED line or unread card, with its exact question). Read `_hq/reports/<slug>.md` only when the
user asks for the findings, and summarise it. Never pull a worker's transcript: at most
`orca terminal read --terminal <handle> --limit 40 --json` on a worker whose STATUS has gone quiet
for a long time, to tell stuck from busy.

## Mode 4: follow-ups, approvals, reviews

Messages for a worker go to its terminal, not into this context:

```text
orca terminal send --terminal <handle> --text "<message>" --enter --wait-submit 10 --json
```

Take the handle from `SESSIONS.md`; on `terminal_handle_stale` or after an Orca restart, use
`orca terminal list --worktree path:<worktree path> --json` and update `SESSIONS.md`. Check the
receipt's `accepted`; never resend on silence. Long messages go in a file
(`_hq/briefs/<slug>-2.md`) and the send points at it. The same applies to "give this to the X
orca session": find its terminal with `orca terminal list --json` and send. A worker started
as a chat has no handle: append `HH:MM hq NOTE <slug> <message>` to `STATUS.md` (its brief
tells it to read lines for its slug) and tell the user it cannot be reached directly. A
follow-up to a worker still on its main job ends with: "When this is done, append a DONE-STEP
line; DONE stays for the whole task."

Reviews go out too. A reviewer is a worker whose brief is "review <PR or branch> against
<brief path>; write PASS or REVISE with numbered items to `_hq/reviews/<slug>.md`; append a
STATUS line". On REVISE, send the author: "Reviewer verdict: REVISE. Read <review path> and fix
every item, then append a REVISED line." and append `HH:MM hq REOPENED <slug>`. Any follow-up
that gives a DONE worker new work is a REOPENED line too, so the watcher tracks it again.

## Mode 5: cleanup ("close the worktree if we're done", "do a cleanup")

For each task in `SESSIONS.md` (or each worktree the user named):

1. Done means: a DONE line, and its PR merged or closed (or `no-code`), and
   `bash <skill dir>/bin/closable.sh <path>` prints `CLOSABLE` (a clean tree, and every commit on
   a remote branch or the head of a merged PR) or `GONE` (the worktree is already removed).
2. Done → `GONE`: append `HH:MM hq CLOSED <slug> already removed` and do not run
   `orca worktree rm`. Otherwise, copy anything worth keeping out of the worktree first (reports
   already live in `_hq/`), then `orca worktree rm --worktree path:<path> --force --json`, and
   append `HH:MM hq CLOSED <slug>`. `--force` is safe only after `CLOSABLE`.
3. Not done → do not remove it. List it with what is missing (`KEEP <why>`, open PR, no DONE
   line). A task you meant to close but cannot gets `HH:MM hq KEPT <slug> <why>`.

HQ runs this on its own, when the watcher wakes it, for every task whose `on-done` ends in close.
When the user asks, report one table (closed / kept and why) and, when asked for "the
knowledge", a short summary built from the DONE lines and reports. Removing a worktree whose
`on-done` is `keep`, or one HQ did not launch, needs the user's OK first.

## Mode 6: watch what you launched

HQ keeps an eye on every worker it started, without reading their transcripts. The watcher is
a background command that sleeps until `STATUS.md` says something HQ must act on, prints only
that, and exits; the exit wakes HQ.

```text
bash <skill dir>/bin/watch.sh <abs path>/_hq [quiet minutes, default 20]
```

`<skill dir>` is the base directory shown when this skill loads.

Run it with the Bash tool's `run_in_background: true` and `timeout: 7200000`. It keeps its own
read offset in `_hq/.watch-offset` and refuses to run twice (`ALREADY-WATCHING`: do nothing).
When it wakes HQ, handle what it printed, then arm it again unless it said `ALL-SETTLED`:

| Output | HQ does |
|--------|---------|
| `DONE` | Check the claim cheaply: `gh pr view <url> --json state,mergeable` and `gh pr checks <url>` for one line of CI truth. Then carry out the slug's `on-done` order (launch a reviewer, merge only if the user ordered it and checks are green). `no-code` → close it now (Mode 5); a foreman's local `DONE <sha>` is not no-code ("Cheap workers"); with a PR the watcher reports the merge later; `keep` → append `hq KEPT <slug> on-done keep`. Launch every task whose `after` is this slug once its condition holds. Tell the user one line. |
| `DONE-STEP` | A follow-up is finished, the main job goes on. Relay it in one line. |
| `HANDOFF <slug> <what>` | Forward it to that worker (Mode 4) without asking the user; launch it instead if it was waiting with `after`. `HANDOFF-FYI` never wakes HQ: the addressee reads it from `STATUS.md`. |
| `WAITING-APPROVAL <slug> <message>` | The worker's agent has sat on a permission prompt for over a minute (its Orca card). Tell the user at once, one line: slug, what it was doing, and that the prompt waits in that worktree's terminal. HQ never answers permission prompts. |
| `PR-MERGED` / `PR-CLOSED <slug> <url>` | The PR left review. Close the worktree (Mode 5), or append `hq KEPT <slug> <why>` when its `on-done` is `keep` or `closable.sh` says `KEEP` (tell the user why). Launch tasks waiting `after` it. |
| `FAILED` | One line with the reason; ask whether to relaunch with a better brief. |
| `ESCALATE` | The foreman ran out of cheap attempts (or stopped on a secret or a branch change). Relaunch on Claude sonnet in the same worktree with the foreman's summary ("Cheap workers"), without asking; tell the user one line. Tasks `after` it keep waiting for the relaunch's DONE. |
| `ANSWER` | Relay the answer in one line. `PREVIEW <url> <login>` and `PUNCH-LIST <path>` go to the user at once, with the URL and login or the screenshots. |
| `BLOCKED` | Put the worker's exact question to the user. Forward the reply (Mode 4). |
| `REVISED` | Launch the re-review, or report if no reviewer is involved. |
| `QUIET <m> <slugs>` | No line from those workers in m minutes. Orca: `orca worktree ps --json` for their cards, then at most `orca terminal read --terminal <handle> --limit 40 --json` to tell busy from stuck from dead. Busy: re-arm silently. Stuck: one nudge ("append a STATUS line with where you are"). Dead (terminal exited): tell the user and offer a relaunch. Subagents: nudge with `SendMessage`. |
| `CHECKPOINT` | Nothing happened for ~2 hours; re-arm silently. The watcher stays armed this way while PRs wait for review. |
| `ALL-SETTLED` | Every dispatched task is FAILED, CLOSED or KEPT, or DONE with no PR waiting for a merge. One summary line per task and stop watching. |

Say nothing to the user for checkpoints and busy workers: silence is the point. If the user is
in the middle of something else when the watcher wakes HQ, keep the event to one line and go
back to what they were doing.

## Without Orca (subagents backend)

Same HQ files, same briefs, same STATUS lines. What changes:

- **Launch** with the Agent tool: `description` = slug, `run_in_background: true`,
  `isolation: "worktree"` when the task edits files (read-only investigations need none),
  `model` only when the user names one. The prompt is the launch prompt from Mode 1 plus:
  "Commit your work on your branch. Your final message is at most five lines: the DONE line,
  the PR or branch, the report path, any open question. Everything longer goes to the report."
  The final message lands in HQ on its own; that limit is what keeps HQ clean.
- **Brief**: drop the Orca card lines (comment, unread) from the Reporting section. The
  worktree starts from HQ's HEAD, so a different base goes in the brief as its first step
  (`git switch -c <branch> origin/<base>`).
- **Fan out**: several Agent calls in one message.
- **SESSIONS.md** gets the agent's name or ID, and later the worktree path and branch from its
  result.
- **Blocked** workers cannot reach the user: they write the BLOCKED line and end with the
  question. HQ asks the user, then sends the answer with `SendMessage` to that agent.
- **Status**: `STATUS.md` tail and `gh` for PRs. Never read a subagent's output file.
- **Watching**: the same watcher; a subagent's completion notice also wakes HQ, handle it like
  its DONE or FAILED line.
- **Follow-ups and reviews**: `SendMessage` to the agent by name or ID; a reviewer is one more
  background subagent.
- **Cleanup**: worktrees without changes are removed automatically. For the rest, apply the
  Mode 5 checks, then `git worktree remove --force <path>` after `CLOSABLE` (and
  `git branch -D <branch>` once merged).
- No remote hosts and no Orca cards; skip those parts.

## Never

- Never do the delegated work in HQ "quickly first".
- Never launch and forget: every dispatch leaves the watcher armed until all tasks settle.
- Never launch a worker with `--agent`, or record one without a terminal handle.
- Never build on a branch the base check has not cleared.
- Never use supervised orchestration (`orchestration worker-start`, `dispatch`, `send`,
  `check --wait`) or ask workers to message HQ.
- Never read whole worker transcripts or diffs into HQ to answer a status question.
- Never put secret values in briefs, STATUS or SESSIONS; point at where they live.
- Never send a brief to the foreman without Acceptance commands and a `Risk:` line, or one that
  writes to production; route it, and let the router send those to Claude.
- Never remove a worktree before `closable.sh` says `CLOSABLE`.
