---
name: delegate
description: "Keep this session as HQ: send substantive work (investigations, fixes, features, PRs, reviews) out as written briefs, one agent each, to Orca worktrees when running in Orca or to background Claude Code subagents in their own git worktrees otherwise, instead of doing it here; HQ then watches them in the background and acts when they finish, fail, ask or go quiet (review, merge on standing orders, launch chained tasks, close worktrees); workers report through a STATUS file (and their Orca card), never by messaging this session; then answer 'how is it going', pass follow-ups and approvals to a worker, and clean up finished worktrees, all without pulling transcripts back into this context. Use when the user says 'open/spool/boot/spin up an orca worktree for this', 'launch some orca worktrees', 'lanza un orca worktree', 'lánzate unos worktrees y a currar', 'monta unos worktrees', 'hazlo en otro worktree', 'give the task to the X orca session', 'mándaselo a la sesión del worktree', 'quédate vigilándolos', 'ves chapando worktrees si han terminado', 'do a cleanup of worktrees', 'close the worktree if we're done', 'bring the summary here', 'keep this session clean', or '/delegate'. Also the DEFAULT for any substantive task, worded or not, whenever the mister-handy SessionStart note says this session is HQ."
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
2. **Write the brief** to `_hq/briefs/<slug>.md`. It must stand on its own: the worker has
   none of this conversation. Use this shape:

   ```markdown
   # <slug>: <one-line goal>

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
   - Acceptance: the test, command output or evidence that proves it is done.

   ## Rules
   - You are on a fresh branch from the repo default base; rename it to the repo's branch
     convention if it has one, and follow its commit conventions.
   - <PR: open it / local commits only / ready-for-review or draft>. Never push to main.
   - Secrets: read <VAR> from <path>; never print or copy secret values.
   - Never bare `git stash`.

   ## Reporting (the only channel back to HQ)
   - Append lines to <abs path>/_hq/STATUS.md: `HH:MM <slug> <STATE> <text>`, STATE one of
     START, MILESTONE, ANSWER, BLOCKED, REVISED, DONE, FAILED (gave up, with why). DONE carries the PR link, commit sha or
     `no-code`, plus the report path if any.
   - Keep your Orca card current: `orca worktree set --worktree active --comment "<state>" --json`.
   - Blocked on a human decision: write a BLOCKED line with the exact question, run
     `orca worktree set --worktree active --unread --json`, and wait in your own terminal.
   - Never message, `terminal send` to, or `orchestration send` to the session that launched you.
   - Long findings go to <abs path>/_hq/reports/<slug>.md, not into STATUS.
   ```

   Time-critical work: ask for an early `ANSWER` line ("within 15 min") before the full job.
3. **Images and drops.** A worker cannot see `[Image #N]` or HQ's attachments, and Orca drop
   paths under `/var/folders/.../orca-drop-*` are temporary. Copy every file the task needs
   into `_hq/assets/<slug>/` and, for pasted images, describe in the brief what they show.
4. **Launch** an independent worktree with the agent in its first terminal:

   ```text
   orca worktree create --repo <selector> --name <slug> --no-parent --agent claude \
     --comment "starting" --prompt "Your task brief is in <abs brief path>. Read it, work autonomously until DONE, and report only as it says (STATUS.md lines and your Orca card). Never message the session that launched you." --json
   ```

   - Omit `--base-branch` so Orca uses the repo default base. Use
     `--parent-worktree active` and the current branch only when the user asks for stacked
     work or "branch from current".
   - `--agent` defaults to `claude`; use another installed agent (`codex`, `pi`, ...) when the
     user names one.
   - The agent handle is `result.agentTerminalHandle` (older runtimes:
     `result.startupTerminal.handle`); if neither is there, take it from
     `orca terminal list --worktree id:<full worktree id> --json`.
5. **Record** a line in `SESSIONS.md`
   (`<slug>  <worktree path>  <handle>  <agent>  <HH:MM>  on-done: <order>  after: <slug|->`)
   and append `HH:MM hq DISPATCHED <slug>` to `STATUS.md`. `on-done` is the user's standing
   order for when it finishes ("review it", "merge if green", "close the worktree"); default
   `report`. `after` names a task this one waits for (Mode 2 chains); such a task is recorded
   but not launched yet.
6. **Report and watch.** One line to the user: slug, worktree, what it will deliver. Then arm the
   watcher (Mode 6) if it is not already running, and end the turn. Never sit waiting in a
   foreground command.

### Model and effort

`--agent claude` uses Orca's configured launcher and takes no per-call model flags. Keep it
unless the user names a model or effort for this task (or names a tool that picks one: use
it). Then create without `--agent` and start Claude yourself:

```text
orca worktree create --repo <selector> --name <slug> --no-parent --json
orca terminal create --worktree id:<full worktree id> --title <slug> --command 'claude --model <model> --effort <level>' --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
orca terminal send --terminal <handle> --text "<the same launch prompt>" --enter --wait-submit 10 --json
```

Send only when the wait reports `satisfied: true`; retry the wait once with a longer timeout,
and if it still fails report the task as not started. If the bare create opened a fallback
shell, close it only after `orca terminal show` confirms it is an unused shell.

### Another host ("en la raspberry")

Find the paired server with `orca environment list --json` and create there with
`--project <projectId> --host runtime:<environment id>` (the project must already have a host
setup there: `orca project setups --json`). HQ files are not reachable from that host, so put
the whole brief in `--prompt` and have the worker report through its Orca card comment and its
PR only; `orca worktree ps --json` shows remote cards. For anything beyond this, read
`orca skills get orca-cli --reference references/placement-and-remote.md`.

## Mode 2: fan out ("lánzate unos worktrees")

1. Split the work into tasks that can run at the same time. **Give every file one owner.**
   Two workers editing the same files end in conflicting PRs; merge such tasks into one worker
   or chain them: write both briefs, launch the first, record the second with `after: <first>`;
   the watcher launches it when the first is DONE and merged.
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
orca session": find its terminal with `orca terminal list --json` and send.

Reviews go out too. A reviewer is a worker whose brief is "review <PR or branch> against
<brief path>; write PASS or REVISE with numbered items to `_hq/reviews/<slug>.md`; append a
STATUS line". On REVISE, send the author: "Reviewer verdict: REVISE. Read <review path> and fix
every item, then append a REVISED line." and append `HH:MM hq REOPENED <slug>`. Any follow-up
that gives a DONE worker new work is a REOPENED line too, so the watcher tracks it again.

## Mode 5: cleanup ("close the worktree if we're done", "do a cleanup")

For each task in `SESSIONS.md` (or each worktree the user named):

1. Done means: a DONE line, and its PR merged or closed (or `no-code`), and
   `git -C <path> status --porcelain` empty, and no commits missing from the remote
   (`git -C <path> log @{u}.. --oneline` empty, or the branch was merged).
2. Done → copy anything worth keeping out of the worktree first (reports already live in
   `_hq/`), then `orca worktree rm --worktree path:<path> --json`, and append
   `HH:MM hq CLOSED <slug>`. Add `--force` only after step 1 proved there is nothing to lose.
3. Not done → do not remove it. List it with what is missing (uncommitted files, open PR,
   no DONE line).

Report one table (closed / kept and why) and, when asked for "the knowledge", a short summary
built from the DONE lines and reports. Removing worktrees the user did not ask to close needs
their OK first.

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
| `DONE` | Check the claim cheaply: `gh pr view <n> --json state,mergeable` and `gh pr checks <n>` for one line of CI truth. Then carry out the slug's `on-done` order (launch a reviewer, close it with Mode 5, merge only if the user ordered it and checks are green). Launch every task whose `after` is this slug once its condition holds. Tell the user one line. |
| `FAILED` | One line with the reason; ask whether to relaunch with a better brief. |
| `ANSWER` | Relay the answer in one line. |
| `BLOCKED` | Put the worker's exact question to the user. Forward the reply (Mode 4). |
| `REVISED` | Launch the re-review, or report if no reviewer is involved. |
| `QUIET <m> <slugs>` | No line from those workers in m minutes. Orca: `orca worktree ps --json` for their cards, then at most `orca terminal read --terminal <handle> --limit 40 --json` to tell busy from stuck from dead. Busy: re-arm silently. Stuck: one nudge ("append a STATUS line with where you are"). Dead (terminal exited): tell the user and offer a relaunch. Subagents: nudge with `SendMessage`. |
| `CHECKPOINT` | Nothing happened for ~2 hours; re-arm silently. |
| `ALL-SETTLED` | Every dispatched task is DONE, FAILED or CLOSED. One summary line per task and stop watching. |

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
- **Brief**: drop the Orca card lines (comment, unread) from the Reporting section.
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
  Mode 5 checks, then `git worktree remove <path>` (and `git branch -d <branch>` once merged).
- No remote hosts and no Orca cards; skip those parts.

## Never

- Never do the delegated work in HQ "quickly first".
- Never launch and forget: every dispatch leaves the watcher armed until all tasks settle.
- Never use supervised orchestration (`orchestration worker-start`, `dispatch`, `send`,
  `check --wait`) or ask workers to message HQ.
- Never read whole worker transcripts or diffs into HQ to answer a status question.
- Never put secret values in briefs, STATUS or SESSIONS; point at where they live.
- Never remove a worktree with uncommitted or unpushed work.
