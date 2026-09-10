# PR Janitor

Keep your open, ready-for-review pull requests healthy without adding review noise.

## What it does

The `/pr-janitor` skill takes a fresh snapshot of each PR (head SHA, checks on that SHA, review threads with author account types), proves which findings are still open on the current head, makes the smallest verified fix, pushes, and reports with direct PR links.

Designed to run unattended from an OpenClaw automation as well as interactively from Claude Code.

## Rules it will not break

- Everything on GitHub and in reports is written in English.
- A finding that is already fixed, outdated, resolved, duplicated or superseded gets no code change and no comment.
- A thread where any human commented is never resolved. Only all-bot threads are resolved, after the fix is verified on the latest head.
- Never merges, closes, relabels, edits the PR description, or force-pushes. Organization repos included.

## Usage

- `/pr-janitor https://github.com/owner/repo/pull/42`
- `/pr-janitor owner/repo` (all your open non-draft PRs there)
- "Keep my open PRs green and handle the review feedback."

The tools are usable on their own:

```bash
skills/pr-janitor/bin/pr-snapshot.sh owner/repo 42 | jq .   # full state of one PR
skills/pr-janitor/bin/pr-fingerprint.sh                      # one line per eligible PR: head, updatedAt, checks, unresolved threads
```

`pr-fingerprint.sh` is meant for a condition trigger: compare its output with the previous run and only wake the agent when a line changed.

## OpenClaw

Point `skills.load.extraDirs` at `automation/plugins/pr-janitor/skills` of a clone of this repo, then schedule it:

```bash
openclaw automations create "0 8-21 * * *" \
  "Use the pr-janitor skill to maintain all my open, ready-for-review pull requests. Follow the skill exactly. If nothing changed and there is no new blocker, return exactly NO_REPLY." \
  --name "PR Janitor" --tz Europe/Madrid --session isolated --announce --channel telegram --to <chat-id>
```

## Requirements

- `git`, `gh` (authenticated, `repo` scope), `jq`

## Plugin structure

```
pr-janitor/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── pr-janitor/
│       ├── SKILL.md
│       └── bin/
│           ├── pr-snapshot.sh
│           └── pr-fingerprint.sh
└── README.md
```
