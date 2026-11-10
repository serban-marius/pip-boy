---
name: jira-write
description: "Write to Jira so it renders correctly and reads well: ticket comments, descriptions, new issues, transition and worklog comments, through either of the two common Jira MCPs. mcp-atlassian (`jira_add_comment`, `jira_update_issue`, `jira_create_issue`, `jira_transition_issue`, `jira_add_worklog`) or Atlassian's own MCP, the claude.ai / Claude Desktop connector (`addOrEditJiraIssueComment`, `editJiraIssue`, `createJiraIssue`, `transitionJiraIssue`, `getJiraIssue`, `mcp__claude_ai_Atlassian_MCP__*`). Load it BEFORE any Jira write instead of pasting Markdown and hoping: it first works out which MCP the session has, then says which format each field really takes there (Markdown, wiki markup or HTML), what breaks, how to edit a posted comment where that is possible, how to reference tickets, PRs and people, how to shape a comment for its news using Jira's own elements (status lozenges, panels, icons, smart-link cards, mentions, tables, screenshots), with a catalogue, templates for both MCPs, a linter for the mcp-atlassian path, and the read-first / confirm / verify steps around posting. Use when the user says 'comment on PROJ-123', 'post this to Jira', 'update the ticket', 'edit my Jira comment', 'leave a status on the ticket', 'write the ticket description', 'create a Jira issue', 'comenta en el ticket', 'actualiza el ticket', 'deja un comentario en Jira', or '/jira-write'."
---

# Write to Jira

Two things go wrong when an agent writes to a ticket. The format: each Jira MCP wants something
different, and the wrong thing shows up as stray symbols or quietly loses half the comment. And
the content: the comment narrates the session instead of telling the next reader where things
stand. This skill covers both.

## 0. Which Jira MCP is this?

The format rules depend on the server, so settle this first. Look at the names of your Jira
tools (load them with ToolSearch if they are deferred):

- **`jira_add_comment`, `jira_get_issue`, `jira_update_issue`** (`mcp__<server>__jira_…`):
  [mcp-atlassian](https://github.com/sooperset/mcp-atlassian). REST v2, wiki markup. The rest of
  this file is written for it, with the evidence in
  [references/formatting.md](references/formatting.md).
- **`getJiraIssue`, `addOrEditJiraIssueComment`, `discover`, `executeRead`**
  (`mcp__claude_ai_Atlassian_MCP__…` in Claude Code): Atlassian's own MCP, the claude.ai /
  Claude Desktop connector. Markdown or HTML, stored as ADF. Its rules are in
  [references/official-mcp.md](references/official-mcp.md); the steps below say where it differs.
- **Both**: pick one for the whole task. The official one when the text needs rich elements or
  may need fixing later, since it can edit a comment.
- **Neither, or another server**: say so. The writing advice and the guardrails still hold; the
  format rules do not, so check that server's conversion yourself.

Side by side:

| | mcp-atlassian | Official Atlassian MCP |
|---|---|---|
| Comment | Markdown subset through a regex converter, plus raw wiki markup | Markdown; `contentFormat: "html"` for lozenges, panels, mentions, cards, checkboxes, media |
| Description | wiki markup, sent as is | same as a comment (`editJiraIssue`, `createJiraIssue`) |
| Fatal mistake | `??` anywhere: the MCP hangs | wiki markup: stored as literal text |
| Fix a posted comment | impossible: post again, the user deletes the old one | edit it: read as HTML, change, write back with its `commentId` |
| Mention | `[~accountid:ID]` | `<span data-type="mention" data-user-id="ID">@Name</span>` |
| A ticket key | renders as a card on its own | stays text: link the browse URL as a smart link |
| A PR | `[PR #39](URL)` | `<a href="URL" data-card-appearance="inline"></a>` |
| Code | link it, the converter mangles blocks | a normal code block |
| Site | configured in the MCP | `cloudId` on every call |
| Before posting | `bin/jira_preview.py` | the nesting rules in official-mcp.md; the script does not apply |
| After posting | compare the stored text with the preview | check `appliedContentFormat` and the echoed body |
| Screenshots | attached by the user, embedded by name | can be uploaded, when the user asks |

Whichever it is, the guardrails are the same: read the ticket first, show the exact text and wait
for a yes, change status only through a transition the ticket offers, and leave deleting to the
user.

## What mcp-atlassian does with your text

On the official MCP, skip to [Steps](#steps); this section is for the `jira_*` tools.

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

mcp-atlassian: `jira_get_issue` with `fields: "summary,status,description,comment,attachment"`,
`comment_limit: 100`, `update_history: false`. The tool returns the *first* N comments, oldest first, so a low limit
hides the recent ones.

Official MCP: `getJiraIssue` gives the ticket and only a comment count. The comments come from
`listJiraIssueComments`, newest first with `orderBy: "-created"`; a page of five is usually
enough to see where the conversation is.

You are looking for:

- **Language.** Write in the language of the description and the latest comments, not the
  language of your session.
- **House style.** If the ticket uses panels, headings or status icons, match them. If comments
  are plain paragraphs, stay plain.
- **What is already said.** Do not repeat the description or the last comment. Add what changed.
- **What is attached.** On mcp-atlassian, screenshots are embedded by their exact file name,
  so take the names from `attachments`; if the user wants screenshots that are not attached
  yet, ask them to drag the files into the ticket first. On the official MCP, see
  [Files](references/official-mcp.md#files).
- **Your own earlier comment.** On the official MCP, a status you posted yourself can be
  brought up to date in place instead of stacking a new one under it. Offer it; do not assume.

### 2. Draft the text

Start from a template in [references/templates.md](references/templates.md): quick status,
status report with panels, blocker, decision record, handoff, checklist, and story, spike and
bug descriptions, each posted and checked rendered through mcp-atlassian; and, at the end, the
HTML versions for the official MCP (quick status, ready for review, status report with a
table, blocker, decision, question). See also
[The comment](#the-comment) below. For a description, keep the structure the project's other
tickets already use: if they open with coloured panels, copy their colours and section titles.

Want a specific element (a panel, a coloured label, a smart-link card, an icon, a table with a
header column)? On mcp-atlassian, look it up in [references/catalogue.md](references/catalogue.md):
every element Jira's editor offers, with the syntax that works through that MCP or, for the
editor-only ones (action items, decisions, status lozenges, dates, expand, layouts), the closest
stand-in. On the official MCP most of those are real elements: the HTML for each is in
[references/official-mcp.md](references/official-mcp.md#elements-in-html).

### 3. Format it

**Official MCP:** plain text goes as Markdown; the moment it needs a lozenge, a panel, a
mention, a card or a checkbox, write HTML and send `contentFormat: "html"`. Before the first
HTML write, fetch the server's own reference with
`executeRead(name="getContentFormatGuide", inputs={"toolName": "addOrEditJiraIssueComment"})`.
Details in [Markdown or HTML](references/official-mcp.md#markdown-or-html). The rest of this
step is for mcp-atlassian.

**mcp-atlassian** comments, in Markdown:

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

The script is for the **mcp-atlassian** path only: it checks Markdown against that MCP's
converter and wiki markup for its descriptions. An HTML body for the official MCP is outside
what it knows: it would flag valid HTML and miss the real traps. Check those by hand against
[what may sit inside what](references/official-mcp.md#elements-in-html): no table in a panel,
no column layout, empty smart-link anchors, a real id in every mention, `&lt;` for `<`.

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

Posting is outward-facing and it notifies watchers. With mcp-atlassian it is also permanent:
**there is no tool to edit or delete a comment**. With the official MCP a comment can be edited
afterwards, but the first notification has already gone out. Before posting, show the user the
ticket (key and summary) and the exact text, and wait for their go.

You may post without asking again only when the user has already seen this text and asked you
to post it, or when you are running an automation whose instructions explicitly authorise
posting on its own. A request from another agent is not the user's approval.

Changing the status, the assignee or any field is a separate action: do it only if asked. A
status change goes through one of the transitions the ticket offers at that moment
(`listJiraIssueTransitions` on the official MCP), not a status name you remember. Removing
anything (a ticket, a comment, a link) is the user's call, made in Jira: say what you would
remove and why.

### 6. Post

One comment per update. Do not split a status into several comments, and do not post a second
one to fix the first without asking. The calls look like this (`fields` is an object, not a
JSON string):

```
jira_add_comment(issue_key="PROJ-123", comment="<the Markdown draft>")
jira_update_issue(issue_key="PROJ-123", fields={"description": "<the wiki markup>"})
```

On the official MCP:

```
addOrEditJiraIssueComment(cloudId="acme.atlassian.net", issueIdOrKey="PROJ-123",
                          contentFormat="html", commentBody="<the HTML draft>")
addOrEditJiraIssueComment(..., commentId="10042", contentFormat="html", commentBody="<the whole edited body>")
editJiraIssue(cloudId=..., issueIdOrKey="PROJ-123", contentFormat="html", fields={"description": "<the HTML>"})
```

A comment for a transition goes in its own `addOrEditJiraIssueComment` call: one passed in the
transition's `update` may be dropped without an error.

To "update" or "fix" a comment already posted, on the official MCP: it is a full rewrite of
that comment, so follow
[Changing what is already there](references/official-mcp.md#changing-what-is-already-there):
read it as HTML, touch only what was asked, keep the old body in your reply, get a yes, write it
back with its `commentId`. Your own comments only.

On mcp-atlassian, the MCP cannot edit or delete one. Post the new version, then ask the user
to delete the old one in Jira (⋯ → Delete). Editing it in place through Jira's REST API with credentials from a config file is only for when the user
explicitly asks for that.

If the call hangs or times out, **the comment has probably been posted**: do not post it again.
Tell the user, and check the ticket once the MCP answers again (or ask them to look). The same
goes for a ticket you were creating: look for it before you create it again.

Updating a description replaces the whole field. Read the current one, keep a copy in your
reply so it can be restored, change only what you were asked to change, and send the complete
text back in wiki markup (mcp-atlassian) or in the HTML you read (official MCP).

### 7. Verify

Official MCP: the comment call returns the `commentId` and the stored body with
`appliedContentFormat`. Check that the format is what you sent and that the status, panel,
cards and mention came back as elements, not as literal tags or `{panel}` text; then give the
user the link. If it came out wrong, show the fix and, with a yes, edit it in place.

mcp-atlassian: read the ticket back (`fields: "comment"`, `comment_limit: 100`, `update_history: false`) and
compare the stored body of the last comment with the script's stdout: Jira stores it byte
for byte.

- **Do not judge from the response of `jira_add_comment`.** It converts the stored text back to
  Markdown and shows damage that is not there (`order_status_code` comes back as
  `order*status*code`).
- `expand: "renderedFields"` does not return rendered HTML through this tool. The read-back
  proves what was stored, not how it looks. Give the user the link to the ticket so they can
  glance at it.
- If it came out wrong, say so, show what is wrong, and ask whether to post a correction or
  leave it for them to edit in Jira. Descriptions you can fix yourself with another update.

## The comment

Written for whoever opens the ticket next: a PM, a tester, the next developer. They scan it in
ten seconds to learn what they need: where things stand, the answer, what is asked of them. Two
failures to avoid: a wall of dense bullets that restates the spec, and a block of text that
says the right things but makes the reader dig for them.

**Pick the shape for the news.** There is no single format. Decide what the reader most needs to
see, then reach for the elements that show it best; [the catalogue](references/catalogue.md)
has every one that renders through mcp-atlassian, and
[official-mcp.md](references/official-mcp.md) the HTML for the official MCP, where a status
lozenge, a task list and a decision are real elements instead of stand-ins. Pairings that work:

| The news | Elements that carry it |
|---|---|
| Shipped, ready to test | a coloured status line, a green titled panel, `(/)` icons, screenshots side by side, the PR as a card |
| Blocked or at risk | a red or yellow titled panel: what is stuck, what would unblock it, a mention of who can |
| Root cause of a bug | the cause in one line up front, a few lines of code or a link to the line, the fix PR as a card |
| Test or QA results | a table of cases with a coloured PASS or FAIL per row |
| A decision | a `(/)` line with the decision, a table of the options for and against |
| A question for someone | a mention and the question, nothing else |
| A small update or a reply | one or two plain lines |

Mix them as the content asks: a release may want a panel and a table, a reply wants neither.
Do not force a status line onto a question, or a panel around two lines. Colours that mean
something: green `#00875a` / panel `#e3fcef` for done, orange `#ff991f` / `#fffae6` for at risk,
red `#de350b` / `#ffebe6` for blocked, blue `#deebff` for information. Icons: `(/)` done, `(!)`
needs attention, `(x)` failing, `(i)` good to know. On the official MCP, use a status lozenge
(`green` done, `blue` in progress or review, `yellow` at risk, `red` blocked) and the panel
types `success`, `warning`, `error`, `info`; the icons above are wiki markup and stay literal
there.

The examples below are mcp-atlassian Markdown; the same shapes in HTML are the official
templates in [templates.md](references/templates.md#official-atlassian-mcp-html).

**Whatever the shape:**

- **Lead with what matters most to the reader**: the state, the answer, the decision, or the
  ask.
- **Short.** It fits on one screen and each bullet fits on one line. Before listing a fifth
  thing, ask whether the reader needs each one; the rest lives in the PR.
- **What the reader can see or do**, not how it works. Mechanics (how requests are split, what
  is cached, which fields exist) belong in the PR: link it.
- **What happens next, and who does it**, when something does happen next.
- **Absolute dates and numbers.** "2026-09-30", "v2.4.0", "48 of 7.9M rows". Not "today",
  "the latest", "most".

Before showing it, skim it the way the reader will: the first line, any bold or panel title,
the first words of each bullet. If that does not tell the story, cut or rearrange until it does.

Leave out:

- The spec or the acceptance criteria, restated. Link them.
- Implementation details, even correct ones.
- Agent narration: "I ran", "in this session", "as requested", "the agent found".
- How you got there: the commands, the dead ends, the debugging story.
- Raw logs and stack traces. Quote the one line that matters and link the rest.
- Secrets and anything that works as one: tokens, passwords, keys, signed URLs, connection
  strings, personal data. A ticket is read, exported and mailed far beyond the team.
- Anything you did not verify, stated as fact.

Too long and too plain, although every word is true:

```markdown
**Done: the read-only product page is live in production in version 2.4.0 (2026-09-30), ready for testing**

- Reads the product from the catalog API across product, market and language, with market, language and version selectors. A switch reloads only the part of the page it changes, and the selection stays in the URL so it can be shared.
- Shows the read-only fields: SKU, category, alias, supplier, the review per market and the file of each version with its download link.
- Values that a language overrides are marked; the mark lists each override next to the base value.

**Pending:** testing in production. Owner: product.
```

The same news, in the shape that fits a release:

```markdown
**Status:** **{color:#00875a}IN PRODUCTION{color}** · v2.4.0 · 2026-09-30

{panel:title=Ready to test|bgColor=#e3fcef}
Open any product from **Search**.
- (/) Switch market, language and version: the URL keeps your choice.
- (/) Language overrides are flagged next to the base value.
- (i) Read-only for now: Save is disabled.
{panel}

||The top of the page, with the selectors||The versions section||
|!product-page-top.png|width=500!|!product-page-versions.png|width=500!|

**Code:** [https://github.com/acme/shop/pull/117|https://github.com/acme/shop/pull/117|smart-link], the last of 13 stacked PRs · [Spec](https://github.com/acme/shop/tree/main/specs/12-product-page)

**Next:** product checks it in production against the acceptance criteria above. Owner: Sam.
```

Other news, other shapes. A root cause:

```markdown
**Root cause:** an empty screenshot list came back as `None` and the cache warmer looped over it. Fixed in [https://github.com/acme/shop/pull/97|https://github.com/acme/shop/pull/97|smart-link].

{code:python}
self.urls = {p.id: p.screenshots or [] for p in programs}
{code}

[~accountid:ACCOUNT_ID] you wrote the original: any idea why it never failed before 2026-09-28?
```

A question, which needs nothing around it:

```markdown
[~accountid:ACCOUNT_ID] can product test the version switch this week? It is live in v2.4.0.
```

### Screenshots

A screenshot earns its place when it shows what words cannot: a new screen, a before and after,
the bug itself. Use the captures you are given as they are.

- **Two go side by side in a table**, with the captions as the header row:
  `||What the first shows||What the second shows||` then
  `|!first.png|width=500!|!second.png|width=500!|`. The width works inside a cell; without it
  each image is a small preview.
- **One on its own gets a width:** `!name.png|width=800!` and a caption in italics under it.
  Without the width, or with `|thumbnail`, it renders as a small preview.
- Jira shows a comment image at most about 250 px tall, so a tall full-page capture stays small
  either way. That is fine: the reader clicks it to open it full size. Say in the caption what
  to look at.
- **One or two.** More belong in the PR.

mcp-atlassian cannot upload files: it runs in Docker, without your files. An image has to be
attached to the ticket first, by the user dragging it into Jira, and is then embedded by its file name.
Do not upload through another route, such as calling Jira's REST API with credentials taken
from a config file, unless the user explicitly says so. The official MCP can upload
(`uploadAttachmentToJiraIssue`, see [Files](references/official-mcp.md#files)); do it
only when the user asked for that file to go on the ticket.

## Referring to things

The forms below are for mcp-atlassian. The official MCP's are in
[People, tickets, PRs](references/official-mcp.md#people-tickets-prs): there a key is only
text until you link its browse URL as a smart link, a PR is a smart link too, and a mention
needs a real account id.

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
