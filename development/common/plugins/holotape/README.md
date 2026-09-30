<div align="center">

# 📼 Holotape

**Your agent writes Markdown. Jira shows something else.**

A Claude Code skill that makes agents write Jira comments and descriptions that render right the
first time and read like a teammate wrote them.

![Claude Code skill](https://img.shields.io/badge/Claude_Code-skill-D97757)
![version](https://img.shields.io/badge/version-1.1.0-blue)
![tests](https://img.shields.io/badge/tests-37_passing-brightgreen)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## The problem

The [mcp-atlassian](https://github.com/sooperset/mcp-atlassian) server tells your agent that
`jira_add_comment` takes *"Comment text in Markdown format"*. It doesn't, quite. The text goes
through a list of regex replacements that turn it into Jira wiki markup, and they don't know
Markdown from a code block:

| Your agent sends | Jira shows |
|---|---|
| `* **Status:** deployed` | `_ __Status:_* deployed` |
| `CacheWarmer.__init__`, even inside a code block | `CacheWarmer.*init*` |
| `Dict<String, List<Url>>` | `Dict[String, List<Url]>` |
| `---` between two sections | the line above becomes a heading |
| an indented sub-bullet | a flat list |
| `why did this ever work??` | it posts, then the MCP spins at 100% CPU and every later Jira call hangs |

And there's more:

- **Descriptions aren't converted at all.** Markdown in a ticket description renders as a mess
  of literal `**`, backticks and broken links.
- **The MCP can't edit or delete a comment.** Whatever goes out stays out.
- **Agents write for themselves.** "I ran the tests and found…" helps nobody who opens the ticket
  next week.

## What the skill does

Before any Jira write, the agent loads `jira-write` and follows seven steps:

1. **Read the ticket first:** its language, its style, and what's already been said.
2. **Draft from a template** that's been posted and checked in Jira.
3. **Format with the subset that survives**, plus raw wiki markup where Markdown falls short.
4. **Preview and lint**: the bundled script runs the MCP's own converter offline and points at
   every trap.
5. **Show you the exact text** and wait for a yes.
6. **Post once.** If the call hangs, it has probably landed: never post twice.
7. **Read it back** and compare it byte for byte with the preview.

## The linter

`jira_preview.py` prints what Jira will actually receive, and names every problem with its line
number and the fix:

```console
$ python3 jira_preview.py draft.md > what-jira-gets.wiki
line 3: error: every <x> becomes [x], in code too -> use words, a bare URL or [text](url)
line 5: error: indented bullet renders flat -> write '*- child' at the start of the line
line 9: error: '??' makes the MCP spin forever after posting (its reply converter backtracks), and every later Jira call hangs -> never write '??', even in code
line 12: note: renders as an icon -> fine if you meant one, otherwise reword
3 error(s), 1 note(s)
```

- **Errors** are things the converter will break, and they fail the run.
- **Notes** are things Jira will interpret that you might have meant, like `(/)` becoming ✅.

It runs the converter from the MCP's own Docker image, offline and without credentials. Without
Docker it only lints. `--description` checks wiki markup meant for a description field instead.

## Every element, catalogued

Jira's editor offers about 50 elements. The skill's
[catalogue](skills/jira-write/references/catalogue.md) says, for each one, what to type through
the MCP, in a comment and in a description. Each is marked *rendered* (posted and looked at in
Jira), *converter* (checked offline) or *editor-only*, and the editor-only ones come with the
closest stand-in. Some of what's in there:

- **Panels** in five colours (info, note, success, warning, error), with titles.
- **Smart links**: a GitHub PR as an inline card or a full card, showing its title and
  Open/Merged state.
- **Tables** with header columns, and lists, links, colours, icons or mentions inside cells.
- **Coloured text**, strikethrough, underline, superscript, forced line breaks.
- **A horizontal rule that survives:** `---- ` with a trailing space. Without the space it
  becomes a heading.
- **All 23 icons**, from `(/)` ✅ and `(x)` ❌ to `(flag)` 🚩.
- **Editor-only elements**, with stand-ins: status lozenges become coloured bold text, action
  items become icon bullets, and decisions become a ✅ line with an options table.

## Templates

[Ready to use](skills/jira-write/references/templates.md), all posted and checked rendered:

| Comments | Descriptions |
|---|---|
| Quick status | Story (context, user story, acceptance criteria) |
| Status report with panels | Spike (goals, scope, acceptance criteria) |
| Blocker | Bug (what happens, expected, repro, evidence, impact) |
| Decision record | |
| Handoff | |
| Checklist with icons | |
| Coloured status line | |

A test checks that every template still lints clean.

## Comments that read well

Formatting is half the job. The skill also sets how a ticket comment reads:

- **Outcome first:** done, blocked, deployed, needs a decision.
- **Short:** one screen. The details live in the PR.
- **Links to the evidence:** PRs, dashboards, docs.
- **What's pending, and who has it:** or "unassigned".
- **Absolute dates and numbers**, never "today" or "the latest".
- **Left out:** agent narration, debugging stories, raw logs, secrets, and anything not verified.

## Checked, not assumed

Every rule comes from evidence:

- the converter's source, read straight from the MCP's Docker image;
- about 150 constructs run through that converter offline;
- nine test comments packing about 100 cases, posted to a real Jira Cloud ticket and inspected in
  the browser;
- a head-to-head on 3 realistic tasks: with the skill, agents passed **21/21** checks, and
  without it **18/21**. The misses without it were the kind that ship broken: code pasted
  through the converter, and Markdown in a description.

On the way it found a bug in the mcp-atlassian build it was checked against: catastrophic
backtracking on `??` that hangs the server.

## Install

```
/plugin marketplace add git@github.com:serban-marius/pip-boy.git
/plugin install holotape@pip-boy
```

Then ask your agent to comment on a ticket, update a description or leave a status. The skill
loads on its own, or call it with `/jira-write`.

**Needs:** the mcp-atlassian MCP server with its Jira write tools. Python 3 and Docker are
optional; they let the linter preview the real conversion.

## Limits

- **mcp-atlassian only.** Other Jira servers convert differently; the writing advice still
  applies, the formatting rules don't.
- **Checked against one build** of the server (`cloudutil/mcp-atlassian`, digest in
  [formatting.md](skills/jira-write/references/formatting.md)). If yours differs, set
  `JIRA_MCP_IMAGE` and the preview shows what your build does.
- **Editor-only elements** (real action items, status lozenges, dates, expands, layouts) can't
  be created through wiki markup. The catalogue gives the closest stand-in for each.
- **No file uploads.** The MCP runs in Docker without your files, so it can only embed images
  that are already attached to the ticket.

## Layout

```
holotape/
├── .claude-plugin/plugin.json
├── README.md
└── skills/jira-write/
    ├── SKILL.md                 # the workflow the agent follows
    ├── bin/
    │   ├── jira_preview.py      # preview + lint
    │   └── test_jira_preview.py
    └── references/
        ├── catalogue.md         # every Jira element, and how to get it
        ├── templates.md         # checked comment and description templates
        └── formatting.md        # the evidence behind every rule
```

<div align="center">

*A holotape is a message recorded for whoever finds it later. So is a ticket comment.*

Part of [pip-boy](https://github.com/serban-marius/pip-boy) · MIT

</div>
