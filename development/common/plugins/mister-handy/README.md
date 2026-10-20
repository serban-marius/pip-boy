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
| Delegate | Checks the base (integration branch, superseded branches), writes `_hq/briefs/<slug>.md`, launches the worker in an Orca terminal (`worktree create`, `terminal create --command 'claude --permission-mode auto'`, `terminal send "<read the brief>"`), records its terminal handle, reports one line and stops |
| Fan out | Splits by what the user will see (that slice first, with the first preview), one owner per file, writes every brief, launches all worktrees in parallel |
| Watch | A background watcher on `STATUS.md` wakes HQ only on DONE, DONE-STEP, FAILED, ANSWER, BLOCKED, HANDOFF, REVISED, a merged or closed PR, a worker sitting on a permission prompt (from its Orca card, `WAITING-APPROVAL`), or a quiet worker; HQ verifies the PR, runs the task's standing order (review, merge if green), passes hand-offs between workers, launches chained tasks, and stays silent otherwise |
| Status | Reads the `STATUS.md` tail, `orca worktree ps` and the PRs; never worker transcripts |
| Follow-up | `orca terminal send` to the worker's handle; approvals, revisions, reviewer verdicts |
| Cleanup | Automatic by default: a `no-code` task closes at DONE, a PR task once its PR merges (`on-done: keep` opts out). `bin/closable.sh` proves a worktree holds nothing unique before `orca worktree rm --force`; on demand it lists the rest with what is missing |

HQ files live next to the repo's Orca worktrees, outside every checkout:

```
~/orca/workspaces/<repo>/_hq/
  briefs/  assets/  reports/  reviews/
  STATUS.md     HH:MM <slug> START|MILESTONE|ANSWER|BLOCKED|HANDOFF|HANDOFF-FYI|DONE-STEP|DONE <text>
  SESSIONS.md   slug, worktree path, terminal handle, agent, on-done
```

A worker blocked on a decision writes a BLOCKED line and marks its Orca card unread, then
waits in its own terminal. Workers also read `STATUS.md` for lines addressed to their slug, so
hand-offs between them do not depend on HQ forwarding them; UI tasks post a running preview URL
(`ANSWER PREVIEW <url> <login>`) within ~20 minutes.

## Why not `orca orchestration`

Supervised orchestration injects every worker message into the coordinator session ("You have
1 orchestration message. Run `orca orchestration check`…"), which is the noise this plugin
exists to remove. The skill starts each worker in a plain Orca terminal and talks to it through
files and `terminal send`. It avoids `worktree create --agent`, which may open a chat session
with no terminal to send follow-ups to.

Without Orca the same modes run on the Agent tool (`run_in_background`, `isolation: "worktree"`, `SendMessage` for follow-ups), with HQ files in `~/.claude/hq/<repo>/`.

Needs `git` and `gh`; the Orca backend needs the `orca` CLI, and `jq` for the permission-prompt check.

Tests: `bash skills/delegate/bin/delegate.test.sh`. Specs: [`004-mister-handy-close-worktrees`](../../../../specs/004-mister-handy-close-worktrees/spec.md),
[`005-mister-handy-reachable-workers`](../../../../specs/005-mister-handy-reachable-workers/spec.md).
