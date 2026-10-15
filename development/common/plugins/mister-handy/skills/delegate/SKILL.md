---
name: delegate
description: "Keep this session as HQ: send substantive work (investigations, fixes, features, PRs, reviews) out to Orca worktrees as written briefs, one agent per worktree, instead of doing it here; workers report through a STATUS file and their Orca card, never by messaging this session; then answer 'how is it going', pass follow-ups and approvals to a worker, and clean up finished worktrees, all without pulling transcripts back into this context. Use when the user says 'open/spool/boot/spin up an orca worktree for this', 'launch some orca worktrees', 'lanza un orca worktree', 'lánzate unos worktrees y a currar', 'monta unos worktrees', 'hazlo en otro worktree', 'give the task to the X orca session', 'mándaselo a la sesión del worktree', 'do a cleanup of worktrees', 'close the worktree if we're done', 'bring the summary here', 'keep this session clean', or '/delegate', and whenever this session is acting as the orchestrator."
---

# Delegate to Orca worktrees, keep HQ clean

This session is HQ. Its context is for what the user cares about: decisions, briefs, short
status, approvals. The digging, the diffs, the test runs and the PR babysitting happen in Orca
worktrees, each with its own agent. Everything in this skill serves one rule:

**Nothing a worker does should land in this context unless the user asks for it.**

So workers never message HQ. They append one-line updates to a STATUS file and set their Orca
card comment; HQ reads those files when the user asks. (Supervised `orca orchestration`
runs break this rule: every worker message is injected here as "You have 1 orchestration
message. Run `orca orchestration check`…", dozens of times per run. Do not use
`orchestration worker-start`, `dispatch`, `send` or `check --wait` from this skill.)

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
  SESSIONS.md          slug, worktree path, terminal handle, agent, started
```

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
     START, MILESTONE, ANSWER, BLOCKED, DONE. DONE carries the PR link, commit sha or
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
5. **Record** a line in `SESSIONS.md` (`<slug>  <worktree path>  <handle>  <agent>  <HH:MM>`)
   and append `HH:MM hq DISPATCHED <slug>` to `STATUS.md`.
6. **Report and stop.** One line to the user: slug, worktree, what it will deliver. Do not wait
   for it, read its terminal, or check on it unless the user asks.

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
   or chain them (second brief starts after the first PR merges).
2. Tell the user the split in one line per task, then go without waiting for approval unless a
   task writes to production or the split is a real judgement call.
3. Write all briefs, then launch all worktrees in one message (parallel tool calls). Each brief
   names the other workers and what they own.
4. Report the table (slug, delivers, worktree) and stop.

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
every item, then append a REVISED line."

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

## Never

- Never do the delegated work in HQ "quickly first".
- Never use supervised orchestration (`orchestration worker-start`, `dispatch`, `send`,
  `check --wait`) or ask workers to message HQ.
- Never read whole worker transcripts or diffs into HQ to answer a status question.
- Never put secret values in briefs, STATUS or SESSIONS; point at where they live.
- Never remove a worktree with uncommitted or unpushed work.
