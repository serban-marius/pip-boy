# Jira element catalogue

Every element Jira Cloud's editor offers (its "Browse all elements" list, 2026-09-30), and how
to get each one through the mcp-atlassian tools: what to write in a **comment** (Markdown that
the converter turns into wiki markup) and in a **description** (wiki markup, sent as is).

**Known from:** *rendered* = posted through the tool and looked at in Jira Cloud;
*converter* = only the converter's output was checked; *editor-only* = the editor can make it,
wiki markup cannot, so no agent can post it through this MCP (every syntax tried stayed
literal text). Details and failure cases are in [formatting.md](formatting.md).

## Text

| Element | Comment | Description | Known from |
|---|---|---|---|
| Bold | `**text**` | `*text*` | rendered |
| Italic | `_text_` | `_text_` | rendered |
| Strikethrough | `-text-` (or `~~text~~`) | `-text-` | rendered |
| Underline | `+text+` | `+text+` | rendered |
| Superscript, subscript | `E = mc ^2^`, `H ~2~ O` (space before) | same | rendered |
| Inline code | `` `text` `` | `{{text}}` | rendered |
| Text colour | `{color:#de350b}text{color}` or `{color:green}` | same | rendered, also inside bold, headings and table cells |
| Line break | a newline, or `\\` | same | rendered |
| En dash, em dash | ` -- `, ` --- ` between words | same | rendered |
| Literal `{` `[` `-` | `\{` `\[` `\-` | same | rendered |
| Citation `??x??` | **never**: hangs the MCP | never | rendered, and hung the server |

## Headings

| Element | Comment | Description | Known from |
|---|---|---|---|
| Heading 1–6 | `# T` … `###### T` (space after the hashes) | `h1. T` … `h6. T` | rendered |
| Heading with colour or icon | `### {color:#de350b}Blocked{color} on review`, `### (!) Still open` | `h3. …` | rendered |

## Lists

| Element | Comment | Description | Known from |
|---|---|---|---|
| Bullet list | `- item` | `* item` | rendered |
| Nested bullet | `*- child` at the start of the line, no bold on it | `** child` | rendered |
| Numbered list | not available as a real list: `1. a` / `2. b` lines render as plain numbered lines | `# item`, `## child` | rendered |
| Numbered items under a bullet | `*# child` at the start of the line, no bold on it | `*# child` | rendered |
| List inside a table cell | `\|A\|* one` then `* two\|` on the next line | same | rendered |
| **Action item** (checkbox task) | editor-only. `* [ ]` stays literal. Use `- (/) done thing` and `- (!) open thing: Owner` | same | editor-only |
| **Decision** | editor-only. Use `(/) **Decision:** …`, or a green panel titled Decision | same | editor-only |

## Blocks

| Element | Comment | Description | Known from |
|---|---|---|---|
| Quote | `{quote}` … `{quote}`, or `bq. one line` | same | rendered |
| Divider | `---- ` **with a trailing space** | `----` | rendered (comment) |
| Code snippet | fence ` ```php ` / `bash` / `json` / `diff` / none, LF endings | `{code:php}` … `{code}` | rendered, multi-line JSON too |
| Code snippet with a title | `{code:title=build.sh\|language=bash}` … `{code}` | same | rendered |
| Preformatted text | `{noformat}` … `{noformat}` | same | rendered as a code block |
| Info panel (blue) | `{panel:bgColor=#deebff}` … `{panel}`, or plain `{panel}` | same | rendered |
| Note panel (purple) | `{panel:bgColor=#eae6ff}` | same | rendered |
| Success panel (green) | `{panel:bgColor=#e3fcef}` | same | rendered |
| Warning panel (yellow) | `{panel:bgColor=#fffae6}` | same | rendered |
| Error panel (red) | `{panel:bgColor=#ffebe6}` | same | rendered |
| Panel with a title | `{panel:title=Blockers\|bgColor=#fffae6}` | same | rendered: bold title next to the panel's icon |
| Panel rules | no table inside a panel (Jira splits it around the table); no icon in the first line (the panel adds its own); `borderStyle` is ignored | | rendered |
| `{info}` macro (Confluence family: `{note}`, `{tip}`, `{warning}`) | `{info}` stays literal; the others are not checked. Use `{panel:bgColor=…}` | | rendered (`{info}`) |
| **Expand** (collapsible) | editor-only. `{expand}` stays literal. Keep it short or link the long part | | editor-only |
| **Layouts / columns** | editor-only. `{section}{column}` stays literal | | editor-only |

## Tables

| Element | Comment | Description | Known from |
|---|---|---|---|
| Table with header row | Markdown table with outer pipes and a dashes-only separator, or `\|\|H\|\|H\|\|` | `\|\|H\|\|H\|\|` then `\|c\|c\|` | rendered |
| Header column | `\|\|Status\|live\|` rows | same | rendered |
| In cells | links, inline code, bold, colour, icons, `\\` breaks, bullet lists, mentions | same | rendered |
| Column alignment | not available (`:---` breaks the Markdown table) | | converter |
| Cell background colour ("colourful table") | editor-only: colour the text instead | | editor-only |

## Inline items

| Element | Comment | Description | Known from |
|---|---|---|---|
| Mention | `[~accountid:ID]`, notifies that person. Id: `jira_search` → comment author `account_id` | same | rendered, also in tables |
| Emoji | the Unicode character (✅ ⚠️ 🚀) | same | rendered |
| Emoji shortcode `:name:` | stays literal | | rendered |
| Icons | `(y)` `(n)` `(i)` `(/)` `(x)` `(!)` `(+)` `(-)` `(?)` `(on)` `(off)` `(flag)` `(flagoff)` `(*)` `(*r)` `(*g)` `(*b)` `(*y)` `:)` `:(` `:P` `:D` `;)` | same | rendered, all of them, anywhere in a line |
| **Status lozenge** | editor-only (`{status:…}` in any form stays literal). Use coloured bold: `**{color:#00875a}ON TRACK{color}**`, `#ff991f` at risk, `#de350b` blocked | same | editor-only; the colour form rendered |
| **Date** | editor-only (`{date}` stays literal). Write it: `2026-10-01` or `1 Oct` | | editor-only |

## Links and media

| Element | Comment | Description | Known from |
|---|---|---|---|
| Link | `[text](https://…)` | `[text\|https://…]` | rendered |
| Ticket | bare `PROJ-123` or `[PROJ-123]`: a card with summary and status | same | rendered |
| Ticket with other text | not available: `[text\|PROJ-123]` stays literal. Use `[text](https://…/browse/PROJ-123)` | | rendered |
| Smart link, inline card | `[https://…\|https://…\|smart-link]`: GitHub PRs show title and Open/Merged | same | rendered |
| Smart link, block card | `[https://…\|https://…\|smart-card]`: title, author, state, description | same | rendered |
| Smart link, embed | `[https://…\|https://…\|smart-embed]`: embeds a whole ticket view, editable fields included. Avoid | | rendered |
| Link to a comment | `[text](https://…/browse/PROJ-1?focusedCommentId=ID)` | same | rendered |
| Email | `[mailto:me@example.com]` | same | rendered |
| Anchor | `{anchor:name}` and `[text](#name)` | same | rendered |
| Image already attached to the ticket | `!file.png!`, `!file.png\|thumbnail!`, `!file.png\|width=200!`, `!file.png\|align=center,width=150!` | same | rendered |
| Image at a readable size | `!file.png\|width=800!`. Comment images show at most about 250 px tall; a wide image then fills the column, a tall capture stays small and opens full size on click. No width, or `\|thumbnail`, renders a small preview | same | rendered |
| Two images side by side | a table: `\|\|caption\|\|caption\|\|` then `\|!a.png\|width=500!\|!b.png\|width=500!\|`. The width works inside a cell; without it each image is a small preview | same | rendered |
| Attachment as a file card | `[^file.png]` | same | rendered |
| External image | `!https://…/image.png!` (renders large) | same | rendered |
| Upload a new file | not possible: the MCP runs in Docker without the host's files mounted, so `attachments` paths do not exist for it | | seen: `Permission denied: '/private'` |

## Editor-only, no wiki equivalent

Action items, decisions, status lozenges, dates, expand, layouts, cell backgrounds, emoji
picker shortcodes, Jira work item lists (JQL tables), Assets, Confluence lists, Dropbox and
other embeds, Rovo, and the "Snippet" templates (incident summary, bug report, project status
snapshot, decision log …). The snippets contain placeholders, and Jira refuses to save a
comment while any are unfilled ("We couldn't save your comment"). If one of these really
matters, draft the comment and ask the user to add that element in the editor.
