# 008 · overseer salvage: prose annotations, commit block and size notes

## Why

Two stale PRs predate the split of `overseer.sh` into small sourced files (#66) and the 0.3.0 red
gate (#69), so neither can be rebased onto `main`.

- #40 (`feat/overseer-rework-comments`) added `hooks/prose.awk` and a commit-time prose check. On
  `main`, `hooks/post-edit.sh` still drops every line holding `@[A-Za-z]`, so
  `@param list<string> $x facts using these terms ...` and `@todo clean this up` pass, and
  `pre-bash` never blocks a commit that adds prose.
- #41 (`feat/overseer-rework-size`) added `hooks/size.awk` and size checks at edit and commit time.
  Nothing of it is on `main`. Blocking commits on a heuristic parser was too risky, and its limits
  caused false positives on inline-HTML PHP templates and JS IIFEs.

This spec rescues the substance of both as one change.

## What changes

### R1 · Prose after an annotation is prose

`hooks/prose.awk` from #40 classifies added comment lines. It is used by `post-edit` instead of the
grep chain, so:

- bare annotations pass: `@param <type> $name`, `@return <type>`, `@var <type>`, `@throws <type>`,
  `@extends`, `@implements`, `@template T`, `@template T of Foo`, and the
  `phpstan-`/`psalm-` typed forms;
- anything after the type or the variable is prose, including
  `@param list<string> $terms facts using these terms never reach the writer` and
  `@template T explanation`;
- tool directives pass whole (`phpcs:`, `phpstan-`, `eslint-`, `noqa`, `@dataProvider`, `@covers`,
  biome/deno/ruff/mypy directives, attributes and shebangs); directive words are anchored to their
  real shapes, so prose that merely starts with `global` or `region` is still prose;
- `@see`, `@todo`, `@deprecated` with text, `@testing` and any other tag followed by text are prose;
  the same tags stay allowed when bare. A `@method` signature passes while it ends in `)`, and text
  after the closing `)` is prose;
- a docblock line whose `*` touches its text (`*Note this explains ...`) is prose too, while code
  lines that begin with `*` (`*args,`, `*p = 0;`) stay code;
- a one-line `ponytail:` marker stays allowed.

The post-edit block stays as it is today. `git commit` is also blocked while a dirty commented file
adds prose. The message lists `file:line` and uses the same text style as the post-edit block. Its
rule is `bash-prose`, separate from `bash-green` and the other commit rules, so stats and the
3-strike escalation count it on its own. `git commit --allow-empty` is checked too, because the
staged set cannot be known before a `git add` running in the same command; the prose check always
covers the whole dirty worktree. Dirty scanning reads porcelain's NUL records, so a renamed file is
checked at its new path and a filename containing `&` or `|` is reported without breaking the
message.

### R2 · Size is a note, never a gate

`hooks/size.awk` is ported from #41 with softer limits:

| Metric | Limit |
|---|---|
| Lines in a function body (no blank or comment lines) | 30 |
| Nesting depth inside a function | 3 |
| Parameters (constructors exempt) | 5 |
| Code lines in a file that defines functions | 300 |

After an edit of a production file, the hook names each function the edit touched that exceeds a
limit. A file over the line limit is named too. Nothing else is reported: tests, docs, data-only
files and untouched legacy functions stay quiet.

The note is advice. It never blocks: PostToolUse JSON on stdout,
`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}`, exit 0. A size
note never touches `git commit`. When a prose block and a size note apply to the same edit, the
block wins (exit 2); its stderr may append the size note.

The parser keeps #41's `LC_ALL=C` handling and heuristic: brace languages by brace matching, Python
by `def` and indentation. The known misreads must not produce a note: an inline-HTML PHP template
with control blocks and a JS IIFE are not functions to measure, and neither `anonymous` nor control
keywords are reported as function names.

### Docs and version

Rule 7 in `rules/overseer.md` names the annotation rule and the commit block; a new short item says
size notes are advice, not a gate. The plugin README carries the same changes. The version goes
from 0.3.0 to 0.4.0 in `plugin.json` and only its own `.claude-plugin/marketplace.json` entry.

## How we'll know it works

`hooks/overseer.test.sh` gains cases, written first and seen failing:

- prose after `@param`/`@return`, `@see`/`@todo`/`@deprecated` with text and a JSDoc description are
  flagged; bare annotations, array shapes, callables, variadics, directives, bare markers and
  `ponytail:` pass;
- a dirty file with prose blocks `git commit` as `bash-prose`, including a config-only commit; a
  dirty file with only bare annotations commits;
- a touched function over 30 body lines, 3 nesting or 5 parameters, and a file over 300 code lines,
  produce a PostToolUse note with exit 0; the same code at the limits, constructors, tests and
  untouched legacy functions stay quiet;
- an inline-HTML PHP template and a long JS IIFE produce no size note;
- an oversized dirty file never blocks `git commit`;
- if an edit adds both prose and oversized code, the edit exits 2 with the prose block.

Sources: #40 `feat/overseer-rework-comments` (R1) and #41 `feat/overseer-rework-size` (R2).
