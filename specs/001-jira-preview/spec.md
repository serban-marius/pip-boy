# 001 · jira-preview: see and lint what Jira will receive, before posting

## Why

The mcp-atlassian MCP cannot edit or delete a comment, and its Markdown converter breaks many
constructs silently (`references/formatting.md` in the `jira-write` skill lists them). An agent
that skims the table still posts broken text. A script that names each problem, with its line
and the fix, is harder to skip than a table.

## What changes

A script in the `jira-write` skill: `skills/jira-write/bin/jira_preview.py`.

```
jira_preview.py [--description] [--no-convert] [FILE]
```

Reads FILE, or stdin.

**Comment mode** (default). The input is the Markdown an agent would pass as `comment`.

- Prints what Jira will receive on stdout: the input run through the converter of the MCP's own
  image, offline (`docker run` of `$JIRA_MCP_IMAGE`, default `cloudutil/mcp-atlassian:latest`).
- Prints one warning per problem on stderr: `line N: <what goes wrong> -> <what to write>`.
- `--no-convert`, or Docker missing or failing: skips the conversion, says so on stderr, still
  lints.

Problems it reports, each from a checked row of `formatting.md`:

| Input | Warning |
|---|---|
| `* item` with `**` or `__` on the line | bullet garbled, use `- ` |
| Indented `- ` or `* ` bullet | renders flat, use `*- child` at the start of the line |
| `*-` / `*#` line with bold | nested line garbled, drop the bold |
| Indented `1.` | renders an empty item, write `1.` at the start of the line |
| `# item` style line with no space after the hashes (`#39`) | becomes a heading |
| A line of only `-`, `*`, `_` or `=` (3+) | the line above becomes a heading |
| `<...>` | becomes `[...]` |
| `__word__` | becomes bold |
| Two or more single `*` on a line, outside `**` | turn into `_` |
| `> quote` | stays literal, use `{quote}` |
| `![alt](url)` | embedded external image, use a link |
| `[text](url)` with `(` in the URL, `__` in the URL, or a title | link breaks |
| Table separator with `:` | table not converted |
| Fence with a language that is not a single word, `~~~` fence, CRLF | fence not recognised |
| `(i)` `(y)` `(n)` `(on)` `(off)` `(x)` `(/)` `(!)` `(?)` `(+)` `(-)` `(*)` `(flag)` in prose | renders as an icon |
| `+word+` | renders underlined |
| `@name` | not a mention |
| `:shortcode:` | stays literal |
| `- [ ]` task box | stays literal brackets |

**Description mode** (`--description`). The input is wiki markup for a `description`, which is
sent as is. Prints the input unchanged on stdout and warns about Markdown left in it: `**bold**`,
`#`-headings, backticks, `[text](url)`, fences.

Exit code: 0 with no warnings, 1 with warnings, 2 on bad usage.

## How we'll know it works

`bin/test_jira_preview.py` (stdlib `unittest`, no Docker needed):

- each problem above produces its warning with the right line number;
- the safe subset (`**bold**`, `- ` bullets, `*- child`, `1.` at column 0, inline code, links,
  `### headings`, Markdown tables, `{quote}`, `{panel}`) produces no warning;
- the example comment in `SKILL.md` lints clean;
- description mode flags Markdown and passes clean wiki markup;
- `--no-convert` prints the input, the warnings, and exits 1 when there are warnings, 0 when not.
