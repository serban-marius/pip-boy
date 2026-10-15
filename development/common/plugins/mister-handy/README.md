# Mister Handy

Keep the main Claude session as HQ: small, responsive, holding only the context you care
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
| Delegate | Writes `_hq/briefs/<slug>.md`, `orca worktree create --agent claude --prompt "<read the brief>"`, records it, reports one line and stops |
| Fan out | Splits the work with one owner per file, writes every brief, launches all worktrees in parallel |
| Status | Reads the `STATUS.md` tail, `orca worktree ps` and the PRs; never worker transcripts |
| Follow-up | `orca terminal send` to the worker's handle; approvals, revisions, reviewer verdicts |
| Cleanup | Removes worktrees that are DONE, merged and clean; lists the rest with what is missing |

HQ files live next to the repo's Orca worktrees, outside every checkout:

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

Without Orca the same modes run on the Agent tool (`run_in_background`, `isolation: "worktree"`, `SendMessage` for follow-ups), with HQ files in `~/.claude/hq/<repo>/`.

Needs `git` and `gh`; the Orca backend needs the `orca` CLI (worktree create with `--agent`/`--prompt`).
