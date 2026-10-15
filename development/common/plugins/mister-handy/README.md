# Mister Handy

Keep the main Claude session as HQ: small, responsive, holding only the context you care
about. Substantive work goes out to Orca worktrees, one agent each, with a written brief.
Workers report through a shared `STATUS.md` and their Orca card, never by messaging HQ, so
nothing they do lands in your main context until you ask for it.

## Install

```
/plugin install mister-handy --marketplace serban-marius/pip-boy
```

## Skill

`/mister-handy:delegate`, or just say "open an orca worktree for this", "lánzate unos
worktrees", "mándaselo a la sesión del worktree", "¿cómo va?", "do a cleanup of worktrees".

| Mode | What HQ does |
|------|--------------|
| Delegate | Writes `_hq/briefs/<slug>.md`, `orca worktree create --agent claude --prompt "<read the brief>"`, records it, reports one line and stops |
| Fan out | Splits the work with one owner per file, writes every brief, launches all worktrees in parallel |
| Status | Reads the `STATUS.md` tail, `orca worktree ps` and the PRs; never worker transcripts |
| Follow-up | `orca terminal send` to the worker's handle; approvals, revisions, reviewer verdicts |
| Cleanup | Removes worktrees that are DONE, merged and clean; lists the rest with what is missing |

HQ files live next to the repo's worktrees, outside every checkout:

```
~/orca/workspaces/<repo>/_hq/
  briefs/  assets/  reports/  reviews/
  STATUS.md     HH:MM <slug> START|MILESTONE|ANSWER|BLOCKED|DONE <text>
  SESSIONS.md   slug, worktree path, terminal handle, agent
```

A worker blocked on a decision writes a BLOCKED line and marks its Orca card unread, then
waits in its own terminal.

## Why not `orca orchestration`

Supervised orchestration injects every worker message into the coordinator session ("You have
1 orchestration message. Run `orca orchestration check`…"), which is the noise this plugin
exists to remove. The skill uses Orca handoffs (`worktree create --agent --prompt`) and files.

## Making it the default

A skill triggers on what you say. To make HQ delegate without being asked, add a line to your
global `~/.claude/CLAUDE.md`, for example:

```
In Orca sessions, delegate any substantive task to a worktree with the mister-handy:delegate skill; keep this session for decisions and status.
```

Needs the `orca` CLI (worktree create with `--agent`/`--prompt`) and `gh` for PR state.
