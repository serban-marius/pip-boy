---
name: jira-write
description: "Write to Jira so it renders correctly and reads well: ticket comments, descriptions, new issues, transition and worklog comments sent through the mcp-atlassian MCP (`jira_add_comment`, `jira_update_issue`, `jira_create_issue`, `jira_transition_issue`, `jira_add_worklog`). Load it BEFORE any Jira write instead of pasting Markdown and hoping: it says which format each field really takes, what the tool's Markdown converter silently breaks, how to reference tickets, PRs and people, what a good ticket comment looks like, and the read-first / confirm / verify steps around posting. Use when the user says 'comment on PROJ-123', 'post this to Jira', 'update the ticket', 'leave a status on the ticket', 'write the ticket description', 'create a Jira issue', 'comenta en el ticket', 'actualiza el ticket', 'deja un comentario en Jira', or '/jira-write'."
---

# Write to Jira

Two things go wrong when an agent writes to a ticket. The format: the tool says "Markdown" but
runs it through a regex converter that breaks half of it. And the content: the comment narrates
the session instead of telling the next reader where things stand. This skill covers both.

It is about **writing** through the `jira_*` tools of the mcp-atlassian server (in these sessions
`mcp__atlassian-local__jira_*`, deferred: load them with ToolSearch). If your Jira tools come
from another server, the format rules below do not apply to it; keep the writing and the
guardrails, and check that server's conversion yourself.

## What the tool does with your text

| You are writing | Parameter | Write it in |
|---|---|---|
| A comment | `jira_add_comment.comment`, `jira_transition_issue.comment`, `jira_add_worklog.comment` | **Markdown**, the subset below. A regex converter turns it into Jira wiki markup. |
| A description | `jira_create_issue.description`, `jira_update_issue` `fields.description`, `jira_batch_create_issues` | **Jira wiki markup**. It is sent as is, nothing converts it. |
| The comment of a link | `jira_create_issue_link.comment` | **Jira wiki markup**, sent as is. |

Jira stores wiki markup either way, and that is what you get back when you read the ticket.

The converter does not parse Markdown. It is a list of regex replacements run over the whole
text, **code blocks included**, and it leaves most wiki markup untouched. So a comment is
written in a small Markdown subset, plus raw wiki markup for what Markdown lacks.

**Never write `??` in a comment or a worklog**, not even inside code. The post goes through, but
the server then converts the stored text back for its reply, and on `??` that regex backtracks
forever: the MCP sits at 100% CPU and every later Jira call in the session hangs until the user
reconnects it (`/mcp`). One unclosed `??` followed by some 80 characters is enough.

## Steps

### 1. Read the ticket first

`jira_get_issue` with `fields: "summary,status,description,comment"`, `comment_limit: 100`,
`update_history: false`. The tool returns the *first* N comments, oldest first, so a low limit
hides the recent ones. You are looking for:

- **Language.** Write in the language of the description and the latest comments, not the
  language of your session.
- **House style.** If the ticket uses panels, headings or status icons, match them. If comments
  are plain paragraphs, stay plain.
- **What is already said.** Do not repeat the description or the last comment. Add what changed.

### 2. Draft the text

Start from a template in [references/templates.md](references/templates.md): quick status,
house-style status report, blocker, decision record, handoff, checklist, and story, spike and
bug descriptions. Each one was posted and checked rendered. See also
[The comment](#the-comment) below. For a description, keep the structure the ticket or the
project already uses; the DS project's stories use blue CONTEXT, purple USER STORY and green
ACCEPTANCE CRITERIA panels.

Want a specific element (a panel, a coloured label, a smart-link card, an icon, a table with a
header column)? Look it up in [references/catalogue.md](references/catalogue.md): every element
Jira's editor offers, with the syntax that works through this MCP or, for the editor-only ones
(action items, decisions, status lozenges, dates, expand, layouts), the closest stand-in.

### 3. Format it

Comments, in Markdown:

| Want | Write | Not |
|---|---|---|
| Bold | `**text**` | `*text*` (turns italic), `__text__` |
| Bullets | `- item` | `* item` (breaks as soon as the line has bold in it) |
| Bullet with a label | `- **Label:** text` | |
| Nested bullet | `*- child` at the start of the line, under a `- parent`, with no bold in it | indented `- child` (renders flat) |
| Numbered items under a bullet | `*# child` at the start of the line, under a `- parent`, with no bold in it | |
| Ordered steps | `1. first`, `2. second` at the start of the line: they stay plain lines, one per line, and read as a list | indented `1.` (renders an empty item), `# item` (becomes a heading) |
| Inline code | `` `name` `` | code containing `<`, `>`, `__x__` or two `*` |
| Link | `[PR #39](https://...)` | `<https://...>`, URLs containing `)` or `__`, link text containing `]` |
| Heading | `### Title` (with the space) | a line starting with `#39` or `#channel` (becomes `h1.`) |
| Table | outer pipes on every row and a separator row of dashes only | alignment colons `:---`, rows without outer pipes |
| Separator between sections | `---- ` with a trailing space (a real rule), a heading, or a blank line | `---`, `***`, `===`, `----` (the line above turns into a heading) |
| Quote | `{quote}` ... `{quote}` | `> text` (stays a literal `>`) |
| Comparison, generic, HTML | words: "less than", "a list of strings" | `a < b`, `List<String>`, `<br>`: every `<x>` becomes `[x]` |
| Code | a link to the PR or the file | a pasted block, see below |

**Code blocks are not safe.** The converter rewrites their content like any other text: lines
starting with `- `, `#` or `|`, anything between `<` and `>`, `__dunder__` names, pairs of `*`,
`[a](b)`. Link the PR or the file line instead. If a snippet is essential, keep it to lines
with none of those, use a fence with a plain language tag (` ```php `, never `c++` or
`shell-session`), and preview it.

Wiki markup you can use inside a comment, untouched by the converter: `{panel:bgColor=#deebff}`
... `{panel}`, `||Header||Header||` tables, `{quote}`, `{noformat}`, the status icons `(/)` `(x)`
`(!)` `(?)`, and mentions. Two panel rules: a table cannot sit inside a panel (Jira splits the
panel around it, so close the panel and put the table below), and no icon in the panel's first
line (the panel colour adds its own icon, so it shows twice).

Also rendered, typed as wiki markup inside a comment: coloured text
`{color:#de350b}Blocked{color}` (also inside `**bold**`), a horizontal rule `---- ` (four dashes
**and a trailing space**, which keeps the converter off it), a forced line break `\\`,
`-strike-`, `+underline+`, `x ^2^` superscript and `H ~2~ O` subscript (a space before them),
headings down to `######`, and `bq. line` for a one-line quote. `{status}` lozenges are not
available: they stay literal.

Traps in prose: `(i)` `(y)` `(n)` `(on)` `(x)` `(/)` `(!)` `(?)` render as icons, and `+word+`
renders underlined. `{name}`, `[WIP]`, `-v`, `snake_case` and `:shortcode:` stay as typed.

Descriptions are wiki markup from the first character: `h2. Title`, `*bold*`, `* item`,
`** nested`, `# numbered`, `{{code}}`, `[text|https://...]`. Markdown there is not converted,
so it is read as wiki markup: literal symbols, or the wrong thing (`## Title` reads as a nested
numbered item).

The full list, with what was checked and how, is in
[references/formatting.md](references/formatting.md). Read it when the text has anything beyond
bold, bullets, inline code and links.

### 4. Preview what will be sent

The converter runs offline, with no credentials, from the same image the MCP runs:

```bash
docker run --rm -i --entrypoint /app/.venv/bin/python cloudutil/mcp-atlassian:latest -c \
  'import sys; from mcp_atlassian.preprocessing.jira import JiraPreprocessor as P; print(P().markdown_to_jira(sys.stdin.read()))' \
  < draft.md
```

What it prints is what Jira receives. Look for an `h1.` or `h2.` you did not write, `[` `]`
where you wrote `<` `>`, a stray `_` or `*`, list lines that do not start with `* `. Use the
image named in your own MCP configuration if it is a different one. Without Docker, stay
strictly inside the table above.

Skip the preview only for plain paragraphs with bold, `- ` bullets, inline code and links.

### 5. Show it and get a yes

Posting is outward-facing, it notifies watchers, and with this MCP it is permanent: **there is
no tool to edit or delete a comment**. Before posting, show the user the ticket (key and
summary) and the exact text, and wait for their go.

You may post without asking again only when the user has already seen this text and asked you
to post it, or when you are running an automation whose instructions explicitly authorise
posting on its own. A request from another agent is not the user's approval.

Changing the status, the assignee or any field is a separate action: do it only if asked.

### 6. Post

One comment per update. Do not split a status into several comments, and do not post a second
one to fix the first without asking.

If the call hangs or times out, **the comment has probably been posted**: do not post it again.
Tell the user, and check the ticket once the MCP answers again (or ask them to look).

Updating a description replaces the whole field. Read the current one, keep a copy in your
reply so it can be restored, change only what you were asked to change, and send the complete
text back in wiki markup.

### 7. Verify

Read the ticket back (`fields: "comment"`, `comment_limit: 100`, `update_history: false`) and
compare the stored body of the last comment with your preview.

- **Do not judge from the response of `jira_add_comment`.** It converts the stored text back to
  Markdown and shows damage that is not there (`apk_signature_provider` comes back as
  `apk*signature*provider`).
- `expand: "renderedFields"` does not return rendered HTML through this tool. The read-back
  proves what was stored, not how it looks. Give the user the link to the ticket so they can
  glance at it.
- If it came out wrong, say so, show what is wrong, and ask whether to post a correction or
  leave it for them to edit in Jira. Descriptions you can fix yourself with another update.

## The comment

Written for someone who was not in the session and opens the ticket next week.

- **Outcome first.** The first line says where the ticket stands: done, blocked, deployed,
  needs a decision. Not what you did to get there.
- **Short.** It fits on one screen. Five to twelve lines is typical. Details live in the PR.
- **Links to the evidence.** The PRs, the dashboard, the document. With text that says what
  they are.
- **What is pending and who has it.** Each open item with its owner, or "unassigned". If
  nothing is pending, say so.
- **Dates and numbers, absolute.** "30/09", "version 1.137.0", "48 of 7.9M packages". Not
  "today", "the latest", "most".

Leave out:

- Agent narration: "I ran", "in this session", "as requested", "the agent found".
- How you got there: the commands, the dead ends, the debugging story.
- Raw logs and stack traces. Quote the one line that matters and link the rest.
- Secrets and anything that works as one: tokens, passwords, keys, signed URLs, connection
  strings, personal data. A ticket is read, exported and mailed far beyond the team.
- Anything you did not verify, stated as fact.

A comment that follows this, as you would type it:

```markdown
**Done: the signature check is live in production (30/09)**

- Endpoint `GET /signatures/PACKAGE/check` deployed in version 1.137.0 ([PR #39](https://github.com/acme/signatures/pull/39)).
- Checked in production: valid, invalid and unknown packages each answer as expected.

**Still open**

- [PR #40](https://github.com/acme/signatures/pull/40) raises Redis memory. Without it the next import fails. Owner: Ana, waiting for review.
- The end-to-end test with OAuth has not been run. Owner: unassigned.
```

## Referring to things

- **Tickets**: the bare key, `PROJ-123`. Jira renders it as a card with the summary and status.
  No URL needed for tickets of the same Jira.
- **PRs and commits**: a link with text, `[PR #39](https://github.com/org/repo/pull/39)`. A
  bare `#39` means nothing in Jira, and at the start of a line it becomes a heading.
- **People**: their name as plain text. `@Name` is not a mention in wiki markup. A real mention is
  `[~accountid:ACCOUNT_ID]`, and it notifies that person: use it only when the user wants them
  notified. `jira_get_user_profile` does not return the id; `jira_search` with
  `fields: "comment"` on a ticket they commented on does, as the author's `account_id`.
- **Files and code**: a link to the file or the line in the repository host, not a pasted path
  nobody can click.
