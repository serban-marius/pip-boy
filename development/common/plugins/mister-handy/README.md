# Mister Handy

Keep the main Claude session as HQ, the orchestrator: small, responsive, holding only the context you care
about. Substantive work goes out with a written brief, one agent each: to Orca worktrees when
you run inside Orca, to background Claude Code subagents in their own git worktrees otherwise.
Workers report through a shared `STATUS.md` (and their Orca card), never by messaging HQ, so
nothing they do lands in your main context until you ask for it.

It is the default, not something you ask for: a SessionStart hook tells every session its role.

| Session | Role | Behaviour |
|---------|------|-----------|
| On the repo's default branch, or outside a repo | HQ | Every substantive task goes out through `delegate`, worded or not; only quick answers and one-minute chores stay |
| On any other branch, or detached HEAD | Worker | Does the work itself, never delegates further |

Override per session with `MISTER_HANDY=off|hq|worker`, or per task with "hazlo aquí".

## Install

```
/plugin install mister-handy --marketplace serban-marius/pip-boy
```

## Skill

`/mister-handy:delegate`, or just say "open an orca worktree for this", "lánzate unos
worktrees", "mándaselo a la sesión del worktree", "¿cómo va?", "do a cleanup of worktrees".

| Mode | What HQ does |
|------|--------------|
| Route | `bin/route.sh <brief>` asks Jev which tier fits (`pi <nan model>`, `claude sonnet`, `claude opus`); no runnable Acceptance commands, `Risk: high` or missing, or `Prod: yes` (a deploy, prod DB or infra write; editing production source is not one) go to Claude opus without asking; a Jev failure to sonnet |
| Cheap workers | `bin/foreman.sh` runs `pi` on a NAN model in the worktree, then the brief's Acceptance commands; retries with the failure appended, climbs the ladder (`skills/delegate/ladder`), and writes START, MILESTONE per attempt, DONE or ESCALATE itself; HQ relaunches an ESCALATE on Claude |
| Delegate | Checks the base (integration branch, superseded branches), writes `_hq/briefs/<slug>.md`, launches the worker in an Orca terminal (`worktree create`, `terminal create --command 'claude --permission-mode auto'`, `terminal send "<read the brief>"`), records its terminal handle, reports one line and stops |
| Fan out | Splits by what the user will see (that slice first, with the first preview), one owner per file, writes every brief, launches all worktrees in parallel |
| Watch | A background watcher on `STATUS.md` wakes HQ only on DONE, DONE-STEP, FAILED, ESCALATE, ANSWER, BLOCKED, HANDOFF, REVISED, a merged or closed PR, a worker sitting on a permission prompt (from its Orca card, `WAITING-APPROVAL`), or a quiet worker; HQ verifies the PR, runs the task's standing order (review, merge if green), passes hand-offs between workers, launches chained tasks, and stays silent otherwise |
| Status | Reads the `STATUS.md` tail, `orca worktree ps` and the PRs; never worker transcripts |
| Follow-up | `orca terminal send` to the worker's handle; approvals, revisions, reviewer verdicts |
| Cleanup | Automatic by default: a `no-code` task closes at DONE, a PR task once its PR merges (`on-done: keep` opts out). `bin/closable.sh` proves a worktree holds nothing unique before `orca worktree rm --force`; on demand it lists the rest with what is missing |

HQ files live next to the repo's Orca worktrees, outside every checkout:

```
~/orca/workspaces/<repo>/_hq/
  briefs/  assets/  reports/  reviews/
  STATUS.md     HH:MM <slug> START|MILESTONE|ANSWER|BLOCKED|HANDOFF|HANDOFF-FYI|DONE-STEP|DONE|ESCALATE <text>
  logs/<slug>/  foreman attempts: prompt, pi output, acceptance output, summary.md
  SESSIONS.md   slug, worktree path, terminal handle, agent, on-done
```

A worker blocked on a decision writes a BLOCKED line and marks its Orca card unread, then
waits in its own terminal. Workers also read `STATUS.md` for lines addressed to their slug, so
hand-offs between them do not depend on HQ forwarding them; UI tasks post a running preview URL
(`ANSWER PREVIEW <url> <login>`) within ~20 minutes.

## Cheap workers

Claude stays on deciding what to do and how; implementation goes to open-source models on the NAN
quota when the brief can prove its result. A brief carries `Risk: low|normal|high` and an
`## Acceptance` section (one command per line, run from the worktree root, exit 0 = accepted).
HQ routes it, and on `pi` launches the foreman instead of Claude:

```
route.sh brief  ->  pi nan/glm5.3-flash 0.83 jev        foreman.sh <slug> <brief> <hq dir>
                    claude sonnet 0.41 low-confidence:nan-flash   (Claude, as before)
                    claude opus 1.00 risk-high
```

| Foreman knob | Default |
|--------------|---------|
| `MISTER_HANDY_LADDER` | `skills/delegate/ladder`: `nan/glm5.3-flash` ×2, `nan/deepseek-v4-flash` ×1 |
| `MISTER_HANDY_ROUTE_THRESHOLD` | 0.6 Jev confidence, below it one tier up |
| `MISTER_HANDY_PI_TIMEOUT` / `MISTER_HANDY_CHECK_TIMEOUT` | 1800 s per attempt / 600 s per command |
| `MISTER_HANDY_PI_FLAGS` | extra pi flags; `-ne` (no pi extensions) is always on, and their `.atl/` + `.gitignore` lines are removed anyway |
| `MISTER_HANDY_REVIEW` | off; a NAN model for one read-only review pass, REVISE gets one more round |
| `MISTER_HANDY_HEARTBEAT` | 600 s between `MILESTONE still working` lines during an attempt |
| `MISTER_HANDY_NAN_SLOTS` | 3 pi runs at once per user, machine-wide (the NAN key allows 7 parallel requests) |
| `MISTER_HANDY_RATE_BACKOFF` / `MISTER_HANDY_RATE_RETRIES` | 60 s doubling to 600 s / 5: a 429 is retried without using a ladder try |

The foreman starts only on a clean feature branch. The worker cannot push or use `gh`; the
foreman pushes only when the brief has `PR: ready|draft <base>`, fails attempts that touch files
outside an optional `Scope: <globs>` line, and escalates instead of committing anything that looks
like a secret. Jev's key comes from
`TYPESAFE_API_KEY` or the keychain item `jev`; NAN credentials stay in pi's own config.

## Why not `orca orchestration`

Supervised orchestration injects every worker message into the coordinator session ("You have
1 orchestration message. Run `orca orchestration check`…"), which is the noise this plugin
exists to remove. The skill starts each worker in a plain Orca terminal and talks to it through
files and `terminal send`. It avoids `worktree create --agent`, which may open a chat session
with no terminal to send follow-ups to.

Without Orca the same modes run on the Agent tool (`run_in_background`, `isolation: "worktree"`, `SendMessage` for follow-ups), with HQ files in `~/.claude/hq/<repo>/`.

Needs `git` and `gh`; the Orca backend needs the `orca` CLI, and `jq` for the permission-prompt check. Cheap workers need `pi`, `jq`, `curl` and `perl`.

Tests: `bash skills/delegate/bin/delegate.test.sh`. Specs: [`004-mister-handy-close-worktrees`](../../../../specs/004-mister-handy-close-worktrees/spec.md),
[`005-mister-handy-reachable-workers`](../../../../specs/005-mister-handy-reachable-workers/spec.md),
[`006-mister-handy-cheap-workers`](../../../../specs/006-mister-handy-cheap-workers/spec.md).
