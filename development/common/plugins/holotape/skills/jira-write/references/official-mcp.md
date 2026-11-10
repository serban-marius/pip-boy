# The official Atlassian MCP: what to send and how

Companion to the `jira-write` skill, for Atlassian's own remote MCP server: the one behind the
Atlassian connector in claude.ai and Claude Desktop, which shows up in Claude Code as
`mcp__claude_ai_Atlassian_MCP__*`. You know you are on it when you have `getJiraIssue`,
`addOrEditJiraIssueComment`, `discover` and `executeRead`.

This server does not take wiki markup. It turns Markdown or HTML into Atlassian Document Format
(ADF), the JSON tree Jira Cloud stores every rich-text field in, and turns ADF back into Markdown
or HTML when you read. Nothing in the mcp-atlassian part of the skill (the regex converter, `??`,
the linter) applies here.

## What was checked, and how

| | |
|---|---|
| Server | Atlassian remote MCP, claude.ai connector (`v2:streamable-http`), 2026-11-10 |
| Tool contracts | the schemas and descriptions of the tools named below |
| HTML shapes | `executeRead(name="getContentFormatGuide", inputs={"toolName": "addOrEditJiraIssueComment"})`, the server's own format reference |
| Stored format | Atlassian's public ADF reference (developer.atlassian.com, "Atlassian Document Format") |
| Rendering | **not checked**: nothing in this file was posted to a live ticket |

The server changes. If a tool's own description disagrees with this file, the tool wins; fetch
the guide again before the first HTML write of a session.

## The tools, by job

| To | Call | Worth knowing |
|---|---|---|
| Read a ticket | `getJiraIssue` | Counts comments but does not return them. `responseContentFormat: "html"` returns the description losslessly. |
| Read comments | `listJiraIssueComments` | Pages of up to 100; `orderBy: "-created"` puts the newest first. Ask for `responseContentFormat: "html"` before you edit one. |
| Comment | `addOrEditJiraIssueComment` | No `commentId`: adds. With one: replaces that comment's whole body. Returns the `commentId`. |
| Edit fields or the description | `editJiraIssue` | Every field you pass is set, not appended: labels and other lists go in full. |
| Create a ticket | `createJiraIssue` | `issueType` by name. If the sprint step fails the ticket still exists: its key is in the response. |
| Change status | `listJiraIssueTransitions` (via `executeRead`), then `transitionJiraIssue` with the `transitionId` | Pick the transition whose target status is the one wanted; a transition's name is not its target. |
| Log work | `addOrEditJiraIssueWorklog` (via `executeWrite`) | |
| Find someone's account id | `lookupJiraAccountId` (via `executeRead`) | `atlassianUserInfo` for the signed-in user. |
| Attach a file | `uploadAttachmentToJiraIssue` (via `executeWrite`) | Two phases, see [Files](#files). |
| Anything else | `discover` with what you want to do, then the `execute…` tool it names | Never call an operation name you did not get from your tool list or `discover`. |

**cloudId** goes on every call. The site host (`example.atlassian.net`) works, and so does any
Jira URL the user gave you; with neither, call `getAccessibleAtlassianResources` once and reuse
what it returns. On `executeRead` / `executeWrite` it sits next to `name`, not inside `inputs`.

## Markdown or HTML

Bodies (`commentBody`, `description`) take `contentFormat`: `markdown`, the default, or `html`.

- **Markdown** when the text is paragraphs, bold, italics, links, lists, headings and code.
  It is ordinary Markdown here, converted properly: `**bold**`, `- item`, fenced code blocks.
- **HTML** as soon as the text needs something Markdown has no syntax for: a status lozenge, a
  panel, a mention, a smart-link card, a checkbox, a decision, a date, coloured text, an image.
  A table can go either way; in HTML you also get header columns and cell colours.
- **Editing** anything that already holds those elements: HTML, always. The server says so in
  its own words: Markdown drops media, panels and expands, and leaves statuses and mentions as
  literal text.
- **Wiki markup is never right here.** `{panel}`, `h2.`, `*bold*`, `[~accountid:…]` and
  `[text|url]` are stored as the characters you typed.

HTML rules from the guide:

- Send a fragment: no `<html>`, `<head>` or `<body>`, and no Markdown fence around it.
- Text is HTML text: `&lt;`, `&gt;` and `&amp;` for `<`, `>` and `&`, also inside `<code>`.
- A site can have the HTML format turned off. Then an HTML write is refused, not downgraded.
  Send the plain part as Markdown and tell the user what had to go.

## Elements, in HTML

All from `getContentFormatGuide`. The ADF node each becomes is in brackets.

| Element | HTML |
|---|---|
| Status lozenge (`status`) | `<span data-type="status" data-color="green">SHIPPED</span>`. Colours: `neutral`, `purple`, `blue`, `red`, `yellow`, `green`. |
| Panel (`panel`) | `<div data-type="panel-success"><p>…</p></div>`. Types: `info`, `note`, `success`, `warning`, `error`. |
| Inline smart link (`inlineCard`) | `<a href="URL" data-card-appearance="inline"></a>`: a pill with the target's live title and state |
| Card on its own line (`blockCard`) | `<a href="URL" data-card-appearance="block"></a>` |
| Mention (`mention`) | `<span data-type="mention" data-user-id="ACCOUNT_ID">@Name</span>` |
| Checkbox list (`taskList`) | `<ul data-type="task-list"><li data-type="task-item"><input type="checkbox"> Open item</li></ul>`; add `checked` for done |
| Decision (`decisionList`) | `<ul data-type="decision-list"><li data-type="decision-item" data-state="DECIDED">The decision</li></ul>` |
| Date (`date`) | `<time datetime="2026-11-10">10 Nov 2026</time>`: calendar dates only, never versions |
| Expand (`expand`) | `<details><summary>Logs</summary><p>…</p></details>` |
| Code block (`codeBlock`) | `<pre><code class="language-python">…</code></pre>` |
| Table (`table`) | `<table><thead><tr><th>…</th></tr></thead><tbody><tr><td>…</td></tr></tbody></table>`; `data-background` on a cell from the guide's palette |
| Coloured text (`textColor`) | `<span style="color: #006644">…</span>`, from the guide's palette only |
| Bold, italic, strike, inline code, link | `<strong>`, `<em>`, `<s>`, `<code>`, `<a href>` |

Smart links drop their anchor text: leave it empty. When the words around a link matter more
than the card (`shop#117 (into main)`), a plain `<a href>` with text reads better.

**What may sit inside what.** The converter refuses or flattens the rest:

- A panel takes paragraphs, headings, lists, checkboxes, decisions, code, media, block cards and
  rules. **Not a table**, an expand, a quote or another panel: put the table between two panels.
- A table cell takes the ordinary blocks and cards.
- Lists, panels, tables and cells cannot be empty.
- **No column layouts in Jira** (`<section data-type="layout-…">`): the write is refused, because
  Jira would save an empty field.
- `data-local-id`: leave it off new nodes, the converter makes them; keep the ones you read.

## Changing what is already there

`addOrEditJiraIssueComment` with a `commentId`, and `editJiraIssue` on the description, replace
the whole body. So an edit is a read-modify-write:

1. Read the current body as HTML (`listJiraIssueComments` or `getJiraIssue` with
   `responseContentFormat: "html"`). Bodies Markdown cannot carry come back as HTML anyway;
   `appliedContentFormat` says which you got.
2. Change only what the user asked for. Everything else goes back exactly as read: ids, table
   column widths, media nodes, inline-comment anchors. Media nodes come back without their
   collection; writing them back as read is fine.
3. Put the old body in your reply so it can be restored, show the change, get a yes.
4. Write the whole body with `contentFormat: "html"`.

Edit only comments the signed-in user wrote (`atlassianUserInfo` against the comment's
author): anyone else's comment would change under their name. If a body holds something you do
not recognise, keep it; if the write fails validation, stop rather than send a trimmed body.

## People, tickets, PRs

- **A mention notifies.** Use one only when the person should hear about it; otherwise their
  name as text. The id comes from the user, `lookupJiraAccountId`, or `atlassianUserInfo`. If
  the lookup returns more than one person, ask. If you have no id, write the name: an invented
  id is worse than none.
- **Ticket keys.** A key typed as text is a text node in ADF, nothing more. For a card, link the
  browse URL: `<a href="https://example.atlassian.net/browse/PROJ-123" data-card-appearance="inline"></a>`.
- **PRs and commits.** An inline smart link shows the PR's title and whether it is open or
  merged. Use `block` for the one PR the comment is about.

## Files

The server can attach a file. `executeWrite("uploadAttachmentToJiraIssue")` with `filePath`
returns a shell command; running it uploads the bytes and prints a `fileId`. Then either attach
it to the ticket (second call with `fileId`) or embed it in a body: pass `inlineFileId` and
`inlineFileCollection` to the comment or edit call (it lands at the end), or place a media node
in the HTML. Give a screenshot `data-width="60" data-width-type="percentage"`; without the type
Jira reads the number as pixels.

Only upload what the user asked to put on the ticket. Never point an image at a local path:
conversion does not upload anything.

## Around every write

- **Status changes** only when asked, and only through a transition the ticket offers right
  now (`listJiraIssueTransitions`). A comment passed inside the transition's `update` can vanish
  without an error: post it with `addOrEditJiraIssueComment`.
- **Deleting** a ticket, comment or link is for the user, in Jira. Name what should go.
- **A call that timed out** may have landed. Read the ticket before you send it again; for a
  create, look for the summary in the project first.
- **Fields.** `additional_fields` takes field names and resolves the values; on a bad value the
  error carries the allowed ones. Custom fields are left out of a read unless you ask for
  `view: "evidence"` or name them.
- **Small reads.** `responseFields` or a `view` preset trims a response; read the description
  and a page of comments in separate calls on a long ticket.

## Read it back

The comment call returns the `commentId` and, unless a file was appended, the stored body with
`appliedContentFormat`. It should say `html` if you sent HTML, and the lozenge, panels, cards
and mention should come back as elements, not as `<span …>` text or `{panel}`. Then give the
user the ticket link: the echo shows what was stored, not how it looks. Wrong? Show the fix,
and with a yes, edit it in place with that `commentId`.
