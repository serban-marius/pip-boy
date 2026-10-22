# jira-length: jira_preview notes comments that are too long to be read

## Why
A real Jira comment written with the jira-write skill was accurate and lint-clean, and still bad:
a sentence for a headline, five dense bullets restating the spec, and full-window screenshots as
tiny thumbnails. The linter only knows converter traps, so it said nothing. The skill should ask
for a headline of a few words, short bullets and readable screenshots, and the linter should point
out when a draft does not.

## What we already know
- Plugin: `development/common/plugins/holotape/` (version 1.1.0), skill `skills/jira-write/`.
- Linter: `skills/jira-write/bin/jira_preview.py`, function `lint_comment(text)` returns warning
  objects with `.line`, `.code`, `.severity` (`error` or `note`), `.message`. Notes are declared in
  the `NOTES` dict and raised with `note(n, code)`; notes never fail the run.
- Tests: `cd development/common/plugins/holotape/skills/jira-write/bin && python3 test_jira_preview.py -v`.
  One existing test lints the example comment in `SKILL.md` (the ```` ```markdown ```` fenced block).

## Task
1. Write `specs/002-jira-comment-length/spec.md` (Why / What changes / How we'll know), like
   `specs/001-jira-preview/spec.md`.
2. `jira_preview.py`, comment mode, four new **notes** (severity `note`, never errors), reported
   on the line where they occur:

   | Code | When |
   |---|---|
   | `long-bullet` | a bullet line (`- `, `* `, `+ `, `*- `, `*# `, `1. `) longer than 120 characters in total (exactly 120 is fine) |
   | `long-headline` | the first non-empty line of the comment is bold (starts and ends with `**`) and is longer than 60 characters; a plain first line never gets it |
   | `thumbnail-image` | a Jira image with `thumbnail` among its options, e.g. `!shot.png|thumbnail!` (`!shot.png|width=800!` is fine) |
   | `long-list` | one uninterrupted top-level list (`- `, `* `, `+ `, `1. ` at column 0) reaches five items: the note goes on the fifth item's line, once; four items, or two separate lists, give nothing |

   Each note's message says what to do instead (one line per bullet; a few words; `|width=800`;
   keep the two or three items the reader needs). No new errors for these inputs.
3. `SKILL.md`: the comment section shows a "too long" example comment and then the "as it should
   read" one, as the **first two** ```` ```markdown ```` fenced blocks in the file, in that order.
   The "too long" one triggers `long-headline` and `long-bullet` and no errors; the good one lints
   with no notes at all (an `icon` note is acceptable). Tell the writer to keep the headline to a
   few words, bullets to one line, at most three of them, and screenshots at `|width=800`, not
   `thumbnail`.
4. Bump holotape to 1.2.0 in its `plugin.json` and `.claude-plugin/marketplace.json`.

## Acceptance
- Each case in the table produces its note and no error; the limits (120-character bullet,
  60-character headline, `|width=800` image, four-item list, two short lists) produce nothing.
- Tests for all of it in `test_jira_preview.py`; the whole file is green.
- Commit message in the repo's style, e.g. `fix(holotape): ... (1.2.0)`.
