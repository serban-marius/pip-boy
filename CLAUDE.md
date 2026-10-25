# CLAUDE.md

@AGENTS.md

This file adds only Claude-specific conventions on top of `AGENTS.md`.

## YAML Frontmatter

All markdown content files (`agents/*.md`, `skills/*/SKILL.md`, `rules/*.md`) **must** start with YAML frontmatter — the `---` delimited block at the top of the file. Frontmatter provides machine-readable metadata that Claude Code uses to discover, load, and describe the content. No frontmatter, no discovery.

### Agents (`agents/*.md`)

```yaml
---
name: agent-name
description: One-line description of what this agent does and when to use it
tools: Read, Bash, Grep, Glob, WebFetch
model: inherit
skills: skill-a, skill-b
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Kebab-case identifier |
| `description` | yes | What the agent does — used for discovery and routing |
| `tools` | yes | Comma-separated list of tools the agent can use |
| `model` | no | Model override (`inherit` uses the parent model) |
| `skills` | no | Comma-separated list of skills the agent can load on demand |

### Skills (`skills/*/SKILL.md`)

```yaml
---
name: skill-name
description: "What the skill does and trigger phrases. Use when the user says 'X', 'Y', or '/skill-name'."
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Kebab-case identifier, matches the directory name |
| `description` | yes | What the skill does plus trigger phrases — Claude Code uses this to decide when to invoke it |

### Rules (`rules/*.md`)

```yaml
---
name: rule-name
description: One-line summary of the convention or constraint
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Kebab-case identifier |
| `description` | yes | What convention or constraint this rule defines |

Rules do **not** use sudocode — they are reference documentation (conventions, patterns, gotchas) written in standard markdown.

## Sudocode — Agent Convention

All agents in this marketplace **must** be written using sudocode — a pseudocode convention that replaces free-form prose with structured, scannable instructions. The sudocode body follows the YAML frontmatter. See [`docs/sudocode.md`](docs/sudocode.md) for the full specification and examples.

Key rules:

- Use keywords (`DO`, `READ`, `GATHER`, `CLASSIFY`, `NEVER`, `ALWAYS`, etc.) for clarity
- One instruction per line; indent sub-steps
- Use `-- comment` for context annotations
- Keep `OUTPUT` schemas explicit with named fields
- `NEVER`/`ALWAYS` rules are hard constraints the agent must not violate
