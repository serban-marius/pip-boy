# jira-preview: jira_preview.py, see and lint what Jira will receive before posting

## Why
The mcp-atlassian MCP cannot edit or delete a comment, and its Markdown converter breaks many
constructs silently. `references/formatting.md` in the `jira-write` skill lists them, but an agent
that skims the table still posts broken text. A script that names each problem, with its line and
the fix, is harder to skip than a table.

## What we already know
- Plugin: `development/common/plugins/holotape/`, skill `skills/jira-write/`. The skill docs are
  already merged: `SKILL.md`, `references/formatting.md` (every converter trap, checked against the
  MCP image), `references/catalogue.md`, `references/templates.md`. The spec is
  `specs/001-jira-preview/spec.md`: read it first, it is the contract; this brief only adds the
  Python interface and the exact codes.
- Python 3 stdlib only; tests with `unittest`, no Docker needed for them.

## Task
Write `skills/jira-write/bin/jira_preview.py` and `skills/jira-write/bin/test_jira_preview.py`.

Interface (the module is imported by its tests as `jira_preview`):
- `lint_comment(text) -> list` and `lint_description(text) -> list` of warning objects with
  `.line` (1-based), `.code` (below), `.severity` (`"error"` or `"note"`), `.message` (what goes wrong
  and what to write instead).
- `main(argv, stdin, stdout, stderr, runner=None) -> int` (exit code), plus a `__main__` entry
  using `sys.argv[1:]` and the real streams. `runner(text, image)` returns the converted text; the
  default runner pipes the text through the converter inside `$JIRA_MCP_IMAGE` (default
  `cloudutil/mcp-atlassian:latest`) with `docker run --rm -i`, and raises
  `jira_preview.ConversionError` when Docker is missing or fails.
- Comment mode (default): stdout = the converted text; with `--no-convert`, or when the runner
  raises `ConversionError`, stdout = the input unchanged and stderr says `conversion skipped` (with
  the reason). Description mode (`--description`): stdout = the input unchanged, no conversion.
- Every warning goes to stderr as `line N: error: <message>` or `line N: note: <message>`.
- Exit 0 when there are no errors (notes alone do not fail), 1 with any error, 2 on bad usage.

Comment codes, severity `error` (the converter breaks it); each maps to a row of the spec table:
`star-bullet-bold`, `indented-bullet` (spaces or tab before `- `/`* `), `nested-bold`,
`indented-number`, `hash-no-space` (`#39 is merged`), `rule-line` (a line of only 3+ `-`, `*`, `_`
or `=`; `---- ` with a trailing space is the supported rule and is not flagged, and the message
says to write `'---- '`), `angle-brackets` (`List<String>`, `a < b and c > d`, `<https://...>`; an
empty `<>` is left alone), `dunder` (`__init__`), `stray-stars` (two or more single `*` on a line
outside `**`: `2 * 3 * 4`, `*.log and *.tmp`; one `5*` is fine), `md-quote`, `md-image`,
`bad-link` (URL containing `(` or `__`, a link title, or `[`/`]` inside the link text; the URL ends
at the first `)`, so `[PR #215](url) (purge endpoint)` is fine), `table-align` (`:` in the
separator row), `table-no-pipes` (a separator row without leading/trailing pipes), `bad-fence`
(language that is not one word like ```` ```c++ ````, a `~~~` fence, a fence line ending in CRLF),
`fence-content` (inside a fenced block the converter keeps the first content line but rewrites
later lines starting with `#` or `- `: flag those later lines), `task-box` (`- [ ]`),
`double-question` (`??` anywhere, including inline code and fenced blocks: it hangs the MCP).

Comment codes, severity `note` (the renderer interprets it, maybe on purpose), only in prose, never
inside inline code or fenced blocks: `icon` (`(i)`, `(y)`, `(on)`, `(/)`, ... the list in the
spec), `underline` (`+word+`; `C++` and `1 + 2 + 3` are fine), `at-mention` (`@sam`; an email
address is fine), `shortcode` (`:white_check_mark:`; `10:30:00` and URLs are fine).

Description codes, severity `error`: `md-heading` (a `#`/`##`... line that is not part of a run of
consecutive `#` lines, which are a wiki numbered list), `md-bold` (`**bold**`), `md-backtick`,
`md-link` (`[text](url)`), `md-fence`.

Must produce **no warnings at all**: the safe subset of the spec (`**bold**` headline such as
`**Done: deployed (30/09)**`, `### headings`, `- ` bullets with bold labels, inline code and links,
`*- child`, `*# numbered child`, `1.` at column 0, Markdown tables with plain separators,
`{quote}...{quote}`, `{panel:bgColor=#deebff}...{panel}`, `PROJ-123`, `rated 5* by users`); the
example comment in `SKILL.md` (its first ```` ```markdown ```` block); and clean wiki markup in
description mode (`h3. *CONTEXT*`, `* *Case A:* rejected`, `** nested`, `# one` / `# two` /
`## child` lists, `{{code}}`, `[text|https://x.io]`, `||Head||Head||` tables, `{panel}`).
Every comment template in `references/templates.md` lints with no errors (notes allowed) and every
description template there lints clean in description mode.

## Acceptance
- Each code above fires on its example with the right line number and severity; the clean inputs
  above give an empty list; the CLI behaves as described (`--no-convert` with an indented bullet
  prints the input and `line 2: error:` and exits 1; a note-only input exits 0; a failing runner
  still lints and says `conversion skipped`).
- `test_jira_preview.py` covers it and is green; do not change the skill docs except to fix a real
  mistake.
- Do not bump the version (the docs commit already set 1.1.0). Commit message in the repo's
  style, e.g. `feat(holotape): jira_preview.py previews and lints Jira drafts`.
