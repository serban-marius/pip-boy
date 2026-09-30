# 002 · jira-preview notes comments that are too long to be read

## Why

A real comment written with the skill was accurate and lint-clean, and still bad: a sentence
for a headline, five dense bullets restating the spec, and full-window screenshots as tiny
thumbnails. The linter only knew about converter traps, so it said nothing. The skill now asks
for a headline of a few words, one-line bullets and readable screenshots; the linter should
point out when a draft does not.

## What changes

`jira_preview.py`, comment mode, three new **notes** (they never fail the run, the writer may
have a reason):

| Input | Note |
|---|---|
| A bullet line (`- `, `* `, `*- `, `*# `, `1. `) longer than 120 characters | `long-bullet`: one line each, link the detail |
| The first non-empty line, when bold (`**...**`), longer than 60 characters | `long-headline`: a few words, the ticket says what the work is |
| An image with `thumbnail` (`!x.png|thumbnail!`) | `thumbnail-image`: renders a tiny preview, use `|width=800` |
| A single list reaching five top-level items | `long-list`: keep the two or three the reader needs |

## How we'll know it works

`bin/test_jira_preview.py`:

- each case above produces its note, and no error;
- a 120-character bullet, a 60-character headline and `!x.png|width=800!` produce nothing;
- the "as it should read" example in `SKILL.md` lints with no notes at all, and the "too long"
  example gets `long-headline` and `long-bullet`.
