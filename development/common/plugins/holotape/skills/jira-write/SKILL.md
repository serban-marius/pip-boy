---
name: jira-write
description: "Write to Jira so it renders correctly and reads well: ticket comments, descriptions, new issues, transition and worklog comments sent through the mcp-atlassian MCP (`jira_add_comment`, `jira_update_issue`, `jira_create_issue`, `jira_transition_issue`, `jira_add_worklog`). Load it BEFORE any Jira write instead of pasting Markdown and hoping: it says which format each field really takes, what the tool's Markdown converter silently breaks, how to reference tickets, PRs and people, what a good ticket comment looks like, and the read-first / confirm / verify steps around posting. Use when the user says 'comment on PROJ-123', 'post this to Jira', 'update the ticket', 'leave a status on the ticket', 'write the ticket description', 'create a Jira issue', 'comenta en el ticket', 'actualiza el ticket', 'deja un comentario en Jira', or '/jira-write'."
---

# Write to Jira

Two things go wrong when an agent writes to a ticket. The format: the tool says "Markdown" but
runs it through a regex converter that breaks half of it. And the content: the comment narrates
the session instead of telling the next reader where things stand. This skill covers both.

It is about **writing** through the `jira_*` tools of the
[mcp-atlassian](https://github.com/sooperset/mcp-atlassian) server, whatever name it has in your
MCP config (`mcp__<server>__jira_add_comment`; if they are deferred, load them with ToolSearch).
If your Jira tools come from another server, the format rules below do not apply to it; keep the
writing and the guardrails, and check that server's conversion yourself.

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
status report with panels, blocker, decision record, handoff, checklist, and story, spike and
bug descriptions. Each one was posted and checked rendered. See also
[The comment](#the-comment) below. For a description, keep the structure the project's other
tickets already use: if they open with coloured panels, copy their colours and section titles.

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
`shell-session`), and let the preview script check it.

Anything beyond this table (panels, coloured text, icons, smart-link cards, mentions, images)
is raw wiki markup typed inside the comment; the converter leaves it alone. The syntax for each
element, and the stand-in for the ones only the editor can make, is in
[references/catalogue.md](references/catalogue.md). Two traps in plain prose: `(i)` `(y)` `(x)`
`(/)` `(!)` and friends render as icons, and `+word+` renders underlined.

Descriptions are wiki markup from the first character: `h2. Title`, `*bold*`, `* item`,
`** nested`, `# numbered`, `{{code}}`, `[text|https://...]`. Markdown there is not converted,
so it is read as wiki markup: literal symbols, or the wrong thing (`## Title` reads as a nested
numbered item).

The full list, with what was checked and how, is in
[references/formatting.md](references/formatting.md). Read it when the text has anything beyond
bold, bullets, inline code and links.

### 4. Preview and lint what will be sent

Write the draft to a file and run the script next to this skill (`bin/` in the skill's base
directory):

```bash
python3 <skill-dir>/bin/jira_preview.py draft.md                   # a comment, in Markdown
python3 <skill-dir>/bin/jira_preview.py --description draft.wiki   # a description, in wiki markup
```

- **stdout** is what Jira will receive: the draft run through the converter of the MCP's own
  image, offline, with no credentials. It needs Docker; set `JIRA_MCP_IMAGE` if your MCP runs
  another image. Without Docker it says so and still lints.
- **stderr** lists each problem as `line N: error|note: what goes wrong -> what to write`.
  Errors are things the converter will break: fix every one. Notes are things Jira will
  interpret, such as `(i)` becoming an icon: keep them only if you meant it.
- **Exit code** 1 means there are errors.

Every check comes from a case in `references/formatting.md`, so a clean run means none of the
known traps is in the draft. Run it on every draft; it takes a few seconds.

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
one to fix the first without asking. The calls look like this (`fields` is an object, not a
JSON string):

```
jira_add_comment(issue_key="PROJ-123", comment="<the Markdown draft>")
jira_update_issue(issue_key="PROJ-123", fields={"description": "<the wiki markup>"})
```

If the call hangs or times out, **the comment has probably been posted**: do not post it again.
Tell the user, and check the ticket once the MCP answers again (or ask them to look).

Updating a description replaces the whole field. Read the current one, keep a copy in your
reply so it can be restored, change only what you were asked to change, and send the complete
text back in wiki markup.

### 7. Verify

Read the ticket back (`fields: "comment"`, `comment_limit: 100`, `update_history: false`) and
compare the stored body of the last comment with the script's stdout: Jira stores it byte for
byte.

- **Do not judge from the response of `jira_add_comment`.** It converts the stored text back to
  Markdown and shows damage that is not there (`order_status_code` comes back as
  `order*status*code`).
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
- **Dates and numbers, absolute.** "2026-09-30", "version 1.137.0", "48 of 7.9M rows". Not
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
**Done: the new checkout flow is live in production (2026-09-30)**

- Deployed in version 1.137.0 ([PR #39](https://github.com/acme/shop/pull/39)).
- Checked in production: card, wallet and gift-card payments each complete as expected.

**Still open**

- [PR #40](https://github.com/acme/shop/pull/40) raises the payment timeout. Without it slow banks fail. Owner: Sam, waiting for review.
- The end-to-end test with 3-D Secure has not been run. Owner: unassigned.
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
