# Jira formatting through mcp-atlassian: what was checked

Companion to the `jira-write` skill. Every row says how it is known:

- **converter**: the output of the MCP's own `markdown_to_jira`, run offline. Deterministic for
  the image it was run on.
- **rendered**: posted through the tool and looked at in Jira Cloud.
- **not checked**: nobody looked at the result; it follows how wiki markup is documented.

## What was checked, and how to check again

| | |
|---|---|
| Image | `cloudutil/mcp-atlassian:latest`, digest `sha256:2bc8e9a715b67039ce9c47f7e9a2eeb16891fd8ccca00187290b2939d7cba90d`, built 2025-09-03 |
| Package | `mcp-atlassian` (dev build, reports 0.0.0) on `atlassian-python-api` 4.0.3 |
| API | Jira REST v2: bodies are wiki markup strings, not ADF |
| Converter | `mcp_atlassian/preprocessing/jira.py`, `JiraPreprocessor.markdown_to_jira` |
| Rendering | Jira Cloud, 2026-09-30, the new issue view |

`:latest` moves. If `docker image inspect cloudutil/mcp-atlassian:latest --format '{{index .RepoDigests 0}}'`
prints another digest, run the preview command from the skill on the constructs you care about
before trusting this file.

Which paths convert, from the source of that image:

| Tool | Field | Converted |
|---|---|---|
| `jira_add_comment` | `comment` | yes, `markdown_to_jira` |
| `jira_transition_issue` | `comment` | yes |
| `jira_add_worklog` | `comment` | yes |
| `jira_create_issue`, `jira_batch_create_issues` | `description` | no, sent as is |
| `jira_update_issue` | `fields.description` | no, sent as is |
| `jira_create_issue_link` | `comment` | no, sent as is |

What the tools give back:

- Jira stores the wiki markup exactly as the converter sent it. `jira_get_issue` and
  `jira_search` return it byte for byte, so a read-back proves what was stored, not how it
  renders.
- The response of `jira_add_comment` converts the stored text back to Markdown with the same
  kind of regexes and shows damage that is not there.
- `expand: "renderedFields"` returns no HTML for comments.
- `jira_get_issue` returns the first `comment_limit` comments, oldest first.
- There is no tool to edit or delete a comment.

**`??` hangs the server.** The replies of `jira_add_comment` and `jira_add_worklog`, and the
worklogs `jira_get_worklog` returns, go through `jira_to_markdown`, whose citation regex
`\?\?((?:.[^?]|[^?].)+)\?\?` backtracks exponentially. Measured offline: an unclosed `??` followed
by 40 characters takes 0.07 s, by 80 characters more than 6 s and grows from there, and `??`
inside `{{code}}` is no safer. Seen live on 2026-09-30: the comment was stored, the MCP process
stayed at 100% CPU, and every later call of the session queued behind it until the container was
stopped and the server reconnected. `jira_get_issue` and `jira_search` return raw bodies and are
not affected.

## Comments: Markdown that works

| Markdown | Sent to Jira | Known from |
|---|---|---|
| `**bold**` | `*bold*` | rendered |
| `_italic_` | `_italic_` | converter |
| `- item` | `* item` | rendered |
| `- **Label:** text` | `* *Label:* text` | rendered |
| `- parent` then `*- child` at the start of the next line | `* parent` / `*- child`: a nested bullet | rendered, also with code and a link in the child |
| `- parent` then `*# child` lines | a numbered list (a, b) nested under the bullet | rendered |
| `1. first` / `2. second` at the start of the line | unchanged: plain lines, one per line, numbers as typed | rendered, reads as a list |
| `` `code` `` | `{{code}}` | rendered, also `{{/items/{id}/check}}` with its braces |
| `[text](https://url?a=1#frag)` | `[text\|https://url?a=1#frag]` | rendered |
| `## T`, `### T` | `h2. T`, `h3. T` | rendered |
| Table with outer pipes and a dashes-only separator row | `\|\| A \|\| B \|\|` then `\| 1 \| 2 \|` | rendered, with links, code and bold in cells |
| ```` ```php ```` / ```` ```bash ```` / ```` ``` ```` fences with safe content | `{code:php}...{code}` | rendered as a code block with line numbers |
| `~~gone~~` | `-gone-` | converter |
| One newline inside a paragraph | a line break | rendered |
| Blank line between paragraphs | kept | rendered |
| Blank line before a `- ` list | dropped, the list follows the line above directly | rendered, harmless |
| Accents, `—`, `%`, `&`, emoji characters like ✅ | kept | rendered |

## Comments: Markdown that breaks

What the converter sends, and what Jira then shows where it was looked at.

| You write | Jira receives | Write instead |
|---|---|---|
| `* item` with bold on the line: `* **Label:** text` | `_ __Label:_* text` | `- **Label:** text` |
| Wiki-style `*bold*` | `_bold_`, italic | `**bold**` |
| `__bold__`, and any `__dunder__` name | `*bold*`, `*dunder*` | `**bold**`; put dunder names in a link to the code |
| Two `*` on one line: `2 * 3 * 4`, `*.apk and *.xapk` | `2 _ 3 _ 4`, `_.apk and _.xapk` | words, or one per line |
| Indented `- child` under `- parent` (2 or 4 spaces, or a tab) | rendered flat, same level as the parent | `*- child` at the start of the line |
| `*- **Label:** child` | `_- __Label:_* child` | no bold on nested lines |
| `** child` (wiki nesting) | `__ child` | `*- child` |
| Indented `1. a` | `## a`: rendered as an empty "1." item with a, b under it; an indented `2. b` stays plain text | `1.` at the start of the line |
| `# item` (wiki numbered list) | `h1. item` | `1.` lines, or `*#` under a bullet |
| `---`, `***`, `===`, `----` on a line of their own | the line above becomes `h2.` or `h1.`; after a blank line, an empty `h2. ` | `---- ` with a trailing space for a rule (rendered), or a heading |
| A line starting with `#` and no space: `#39 is merged`, `#deploy` | `h1.39 is merged`, `h1.deploy` | do not start a line with `#` |
| `a < b and c > d`, `List<String>`, `<br>`, `<details>` | `a [ b and c ] d`, `List[String]`, `[br]`, `[details]` | words; no HTML |
| `<https://url>`, `<me@example.com>` | `[https://url]`, `[me@example.com]` | the bare URL, or `[text](url)` |
| `[text](url)` with `)` in the URL | link cut at the first `)` | percent-encode it (`%29`), which passes |
| `[text](url)` or a bare URL with `__` in it | `__x__` in the URL becomes `*x*` | a URL without `__` |
| `[text](url "title")` | the title ends up inside the URL | no title |
| `[[WIP] title](url)` | not converted | no `]` in the link text |
| Table with `:---` or `---:` in the separator | not converted, literal pipes and dashes | dashes only |
| Table without outer pipes | not converted | outer pipes on every row |
| `> quote` | unchanged: a literal `>` (rendered) | `{quote}` ... `{quote}` |
| `![alt](url)` | `!url\|alt=alt!`, an embedded external image | a link |
| `- [ ] todo` | `* [ ] todo` | plain bullets |
| `\*not bold\*` | `\_not bold\_`, escapes are not honoured | rephrase |
| `## Title ##` | `h2. Title ##` | no closing hashes |
| A line of `-` or `=` under any text (`total` then `-`) | the text becomes a heading | never leave one |
| `:white_check_mark:` | unchanged, shows as typed (rendered) | the emoji character, or nothing |

## Comments: code

Inline code: `` `x` `` becomes `{{x}}`, and then the rest of the converter still runs on `x`.

| Inside backticks | Jira receives |
|---|---|
| `apk_file_name`, `my-flag`, `GET /path?x=1`, `/items/{id}/check` | unchanged, rendered fine |
| `__init__` | `{{*init*}}` |
| `List<String>` | `{{List[String]}}` |
| `*.apk` and `**/*.php` on one line | `{{_.apk}}`, `{{__/_.php}}` |
| `{{ .Values.x }}` | `{{{{ .Values.x }}}}` |

Fenced blocks: ```` ```lang ```` + newline + content + ```` ``` ```` becomes
`{code:lang}content{code}` and renders as a code block, but the content is rewritten like
prose first:

| In the block | Jira receives |
|---|---|
| `# install deps` on the first line | unchanged (it follows `{code:bash}` on the same line) |
| `# comment` on any later line | `h1. comment` |
| `- old line`, YAML `  - a` | `* old line`, `  * a` |
| `def __init__(self, *args, **kwargs)` | `def *init*(self, _args, _*kwargs)` |
| `Map<string, number>` | `Map[string, number]` |
| `x[0](y)` | `x[0\|y]` |
| A Markdown table | its header row becomes `\|\| a \|\| b \|\|`, the separator is deleted |
| Language `c++`, `shell-session`, or CRLF line endings | fence not recognised: literal backticks around a `{{...}}` that swallows the whole block |
| `~~~` fences | not converted |
| An indented fence | converted, indentation kept in front of `{code}` |

Raw `{code}` and `{noformat}` written by hand render as code blocks too, and get the same
rewriting inside. There is no container the converter leaves alone. What survives: lines with
no leading `-`, `#` or `|`, no `<...>`, no `__x__`, at most one `*`, no `[a](b)`. JSON on one
line and plain shell commands usually qualify. Everything else: link it.

## Comments: wiki markup that passes through

The converter leaves these alone, so they can be typed as is in a comment.

| Wiki markup | Known from |
|---|---|
| `{panel:bgColor=#hex}` ... `{panel}`, with Markdown headings and `- ` bullets inside | rendered. Jira maps the colour to a panel type with its own icon: `#deebff` info, `#e3fcef` success, `#eae6ff` note, `#fffae6` warning. An icon typed in the panel's first line shows twice |
| A table inside a panel | rendered badly: Jira splits the panel into one before the table and one after, with the table outside. Close the panel and put the table below |
| `\|\|Header\|\|Header\|\|` and `\|cell\|cell\|` rows, inline code in cells | rendered |
| `(/)` `(x)` `(!)` `(?)` | rendered as icons, fine in bullets and table cells |
| `{quote}` ... `{quote}` | rendered as a quote block |
| `{noformat}` ... `{noformat}` | rendered as a code block |
| `[~accountid:ID]` | rendered as a mention, and notifies that person |
| `---- ` on its own line: four dashes and a trailing space | rendered as a horizontal rule. Without the space the converter turns the line above into a heading |
| `line one\\line two` | rendered as a forced line break |
| `{color:#de350b}text{color}`, `{color:green}text{color}` | rendered in that colour; also inside `**bold**` |
| `-strike-`, `+underline+` | rendered |
| `E = mc ^2^`, `H ~2~ O`, with a space before the marker | rendered as superscript and subscript. Glued to the word (`x^2^`) stays literal |
| `#### T`, `##### T`, `###### T` | rendered as h4 to h6 |
| `bq. line` | rendered as a quote |
| `{status:colour=Green\|title=Done}` | stays literal: no status lozenges in wiki markup |
| `??citation??` | rendered as "— citation", but **never use it**: `??` hangs the MCP (see above) |
| `[text\|https://url]`, `{{code}}`, `h2. Title` | converter |
| `{color:red}text{color}` | converter |

Not usable: wiki `*bold*` (becomes `_bold_`), `** nested`, `# numbered`, `----` without the
trailing space, `??citation??`.

## Characters Jira reads as markup

These pass the converter; the renderer decides.

| In prose | Rendered as |
|---|---|
| `(i)` `(y)` `(n)` `(on)`, and `(x)` `(/)` `(!)` `(?)` | icons: info, thumbs up, thumbs down, light bulb, and the four status icons |
| `+word+` | underlined |
| `PROJ-123` | a card with the ticket's summary and status |
| `{name}` | as typed |
| `[WIP]`, `array[0]` | as typed |
| `-v or -x` | as typed |
| `a_b and c_d` | as typed |
| `x^2^` | as typed |
| `-word-`, ` ^word^`, ` ~word~` | strikethrough, superscript, subscript (rendered) |
| `??` anything | hangs the MCP after posting: never |
| Every icon: `(y) (n) (i) (/) (x) (!) (+) (-) (?) (on) (off) (flag) (flagoff) (*) (*r) (*g) (*b) (*y) :) :( :P :D ;)` | rendered, anywhere in a line, alone or adjacent |
| `!word!` | not checked: may become an embedded image |

## Descriptions: wiki markup

Sent as is, so write wiki markup directly: that the tools send descriptions untouched is known
from the converter source, and a test description written through `jira_update_issue` rendered
headings, bold, inline code, links, nested bullets and nested numbered lists as below. The DS
project's descriptions add `{panel:bgColor=...}` and `h3. *TITLE*`, also rendered. Everything
in [catalogue.md](catalogue.md) marked rendered for comments works here too, written as wiki
markup.

| Want | Write |
|---|---|
| Heading | `h2. Title` (a blank line after it) |
| Bold, italic | `*bold*`, `_italic_` |
| Bullets, nested | `* item`, `** child` |
| Numbered, nested | `# item`, `## child` |
| Inline code | `{{code}}` |
| Code block | `{code:php}` newline, code, newline, `{code}` |
| Preformatted text | `{noformat}` ... `{noformat}` |
| Link | `[text\|https://url]` |
| Table | `\|\|Header\|\|Header\|\|` then `\|cell\|cell\|` |
| Panel | `{panel:bgColor=#deebff}` ... `{panel}` |
| Quote | `{quote}` ... `{quote}` |
| Rule | `----` |
| Mention | `[~accountid:ID]` |
| Ticket | `PROJ-123` |

Markdown in a description is not converted, and rendered like this: `## Title` became an empty
numbered item with the heading, and the line after it, as its sub-item; `**bold**`, backticks
and `[text](url)` showed as typed; `- item` did render as a bullet.
