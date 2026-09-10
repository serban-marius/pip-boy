# GitHub Janitor

Two skills that keep GitHub quiet without you: one maintains the PRs you author, the other keeps your notification inbox down to what needs a human. Both are designed to run unattended from OpenClaw automations and interactively from Claude Code.

## Skills

### `/pr-janitor`

Takes a fresh snapshot of each of your open, ready-for-review PRs (head SHA, checks on that SHA, review threads with author account types), proves which findings are still open on the current head, makes the smallest verified fix, pushes, and reports with direct PR links.

- Everything on GitHub and in reports is written in English.
- A finding that is already fixed, outdated, resolved, duplicated or superseded gets no code change and no comment.
- A thread where any human commented is never resolved. Only all-bot threads are resolved, after the fix is verified on the latest head.
- Never merges, closes, relabels, edits the PR description, or force-pushes. Organization repos included.

### `/inbox-janitor`

Snapshots every thread in your GitHub inbox with a rule-based verdict, marks the noise as done, and sends a short digest of what is left.

Marked done: merged/closed subjects, review requests you already approved, review requests on bot-authored PRs (dependabot, updaters), activity on your own PRs, CI/push/subscription chatter. Kept and reported: mentions, assignments, pending reviews on human PRs. It only marks threads done; it never approves, merges or comments. Marked threads are remembered in `~/.local/state/inbox-janitor/done.json` because the notifications API keeps listing done threads.

## Tools

```bash
skills/pr-janitor/bin/pr-snapshot.sh owner/repo 42 | jq .   # full current state of one PR
skills/pr-janitor/bin/pr-fingerprint.sh                      # one line per eligible PR: head, updatedAt, checks, unresolved threads
skills/inbox-janitor/bin/inbox-snapshot.sh | jq .            # every inbox thread with verdict + rule
skills/inbox-janitor/bin/inbox-clean.sh --dry-run            # what would be marked done, and what is kept
```

`pr-fingerprint.sh` is meant for a condition trigger: compare its output with the previous run and only wake the agent when a line changed.

## OpenClaw

Point `skills.load.extraDirs` at `automation/plugins/github-janitor/skills` of a clone of this repo. Suggested jobs:

```bash
# PRs: evaluate every 10 minutes, wake the agent only when a PR changed (see the goldclaw repo for the trigger script)
openclaw automations create "*/10 8-21 * * *" "Use the pr-janitor skill to maintain all my open, ready-for-review pull requests. Follow the skill exactly. If nothing changed and there is no new blocker, return exactly NO_REPLY." \
  --name "PR Janitor" --tz Europe/Madrid --session isolated --announce --channel telegram --to <chat-id> --trigger-script pr-janitor.trigger.js

# Inbox: once a day, always sends the digest
openclaw automations create "0 9 * * *" "Use the inbox-janitor skill: mark the noise as done and send the digest of what needs me. Always send it, even if the inbox is clean." \
  --name "Inbox Janitor" --tz Europe/Madrid --session isolated --announce --channel telegram --to <chat-id>
```

## Guardrails (install before running unattended)

The skills run with your `gh` token, so GitHub cannot tell the agent from you. The `guardrails/` shims replace `/usr/bin/gh` and `/usr/bin/git` on the host and refuse what the janitors must never do, whatever the prompt says: `gh pr merge|close|reopen|edit`, `gh issue close|edit|delete`, `gh repo delete|archive|edit`, `gh api` PUT on `/merge`, PATCH on `/pulls/` or `/issues/`, DELETE under `repos/`, merge/close/delete GraphQL mutations, and `git push` with `--force`, `-f`, `--force-with-lease`, `--delete`, `:branch` or `+ref`.

```bash
automation/plugins/github-janitor/guardrails/install.sh   # Debian/Ubuntu, uses dpkg-divert + sudo, runs test-shims.sh
```

**TODO whenever this plugin is deployed on a new host or agent: run `guardrails/install.sh` first.** Both skills check for `/usr/bin/gh.real` in unattended runs and stop with a blocker if the shims are missing. Pair this with branch protection ("require approvals", no bypass) on the repos that matter: the shims stop the agent, branch protection stops everyone.

## Requirements

- `git`, `gh` (authenticated, `repo` scope), `jq`

## Plugin structure

```
github-janitor/
├── .claude-plugin/
│   └── plugin.json
├── guardrails/
│   ├── gh                # shim: blocks merge/close/edit/delete
│   ├── git               # shim: blocks force-push and remote deletion
│   ├── install.sh        # dpkg-divert install + test
│   └── test-shims.sh
├── skills/
│   ├── pr-janitor/
│   │   ├── SKILL.md
│   │   └── bin/
│   │       ├── pr-snapshot.sh
│   │       └── pr-fingerprint.sh
│   └── inbox-janitor/
│       ├── SKILL.md
│       └── bin/
│           ├── inbox-snapshot.sh
│           └── inbox-clean.sh
└── README.md
```
