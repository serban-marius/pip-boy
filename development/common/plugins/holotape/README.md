# Holotape

Write to Jira so it renders and reads well. A holotape is a message recorded for whoever finds
it later: that is what a ticket comment is.

## What it does

The `jira-write` skill is loaded before an agent posts a comment, a description or an update
through the [mcp-atlassian](https://github.com/sooperset/mcp-atlassian) Jira tools. It settles:

- **The format each field takes.** Comments go through a regex Markdown converter; descriptions
  are sent as raw Jira wiki markup. The tool descriptions do not say so.
- **What the converter breaks, and the form that works instead.** `* ` bullets with bold,
  indented lists, `---` rules, anything between `<` and `>`, `__dunder__` names, and the inside
  of code blocks.
- **How to refer to things.** Tickets by key, PRs by link, people by name, and mentions by
  account id only when someone must be notified.
- **The shape of a ticket comment.** Outcome first, short, links to the evidence, what is
  pending and who has it. No agent narration, no secrets, no raw logs.
- **The guardrails.** Read the ticket first, preview what will be sent, show it to the user
  before posting, read it back after. The MCP cannot edit or delete a comment.

What it says about formatting was checked, not assumed:
[`references/formatting.md`](skills/jira-write/references/formatting.md) records each rule with
how it is known and the image it was checked against.

## Usage

- "Comment on PROJ-123 with where we are"
- "Update the ticket description with the new scope"
- "Leave a status on the ticket"
- `/jira-write`

## Requirements

- The mcp-atlassian MCP server with Jira write tools enabled.
- Docker, optional: the skill previews what will be sent by running the converter from the MCP's
  own image, offline and without credentials.

## Plugin structure

```
holotape/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── jira-write/
│       ├── SKILL.md
│       └── references/
│           └── formatting.md
└── README.md
```
