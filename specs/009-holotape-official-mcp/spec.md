# 009 · holotape: write through Atlassian's own MCP as well

## Why

`jira-write` assumes the mcp-atlassian server: REST v2, wiki markup, a regex Markdown converter,
no way to edit a comment. More sessions now reach Jira through Atlassian's own remote MCP (the
claude.ai / Claude Desktop connector: `getJiraIssue`, `addOrEditJiraIssueComment`,
`contentFormat: markdown|html`). There the skill's advice is wrong in ways that ship broken
comments: it says to send wiki markup (stored as literal text), that a comment cannot be fixed
(it can), and that a bare key renders as a card (it stays text).

## What changes

- `SKILL.md` gets a step 0, **Which Jira MCP is this?**, decided from the tool names, with a
  side-by-side table: format, the fatal mistake, fixing a posted comment, mentions, keys, PRs,
  code, site, checks before and after posting, screenshots. The steps say where the official
  server differs. Everything for mcp-atlassian stays, labelled. The description triggers on the
  official tool names too.
- `references/official-mcp.md`: the official server, worked out from its tool schemas, the HTML
  reference it serves (`getContentFormatGuide`) and Atlassian's public ADF reference. Tools by
  job, Markdown or HTML, the HTML for each element and what may nest in what, the
  read-modify-write for edits, people / tickets / PRs, files, the checks around every write,
  read-back.
- `references/templates.md`: an HTML section with status, ready-for-review, report, blocker,
  decision and question templates.
- `bin/jira_preview.py` is unchanged and stays the mcp-atlassian linter; `SKILL.md` says not to
  run it on HTML. An HTML lint mode is left for later.

## How we'll know it works

`bin/test_jira_preview.py`:

- the wiki and Markdown templates still lint clean, with the HTML section split off;
- there are at least three HTML templates, and none holds wiki markup, Markdown, a document
  wrapper, a column layout, a table inside a panel, a bare `<`, text inside a smart-link card or
  a mention without an id.

By hand: post one HTML template to a test ticket and read it back.
