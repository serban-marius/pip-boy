# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

This is a **Claude Code plugin marketplace** — a curated registry of plugins, maintained as a configuration/documentation repository. There is no build system, no dependencies, and no test infrastructure.

## Repository Structure

Plugins are organized by **category** in top-level directories. Each category contains two subdirectories:

- `plugins/` — Internal plugins maintained by the owner
- `external_plugins/` — Third-party plugins

### Categories

| Directory | Purpose |
|-----------|---------|
| `common/` | General-purpose plugins useful across all projects |
| `development/common/` | Language-agnostic development tools |
| `development/js/` | JavaScript/TypeScript ecosystem plugins |
| `development/php/` | PHP ecosystem plugins |
| `development/python/` | Python ecosystem plugins |
| `infrastructure/` | Infrastructure and SRE plugins |
| `seo/` | SEO and search-related plugins |
| `bi/` | Business Intelligence and analytics plugins |
| `product/` | Product management and design plugins |

### Key Files

- **`.claude-plugin/marketplace.json`** — Central marketplace manifest listing all available plugins with metadata, versions, and categories. Every plugin must be registered here.

## Plugin Anatomy

Every plugin follows this structure:

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata (name, description, version, author, homepage, repository)
├── .mcp.json            # MCP server configuration (transport type, command, or URL)
└── README.md            # Plugin documentation
```

Optional directories: `commands/`, `agents/`, `skills/`, `rules/`.

Skills can also contain subdirectories:
- `skills/{skill-name}/references/` — companion docs loaded on demand by the skill
- `skills/{skill-name}/bin/` — executable scripts the skill invokes

## YAML Frontmatter

All markdown content files (`agents/*.md`, `skills/*/SKILL.md`, `rules/*.md`) **must** include YAML frontmatter — the `---` delimited block at the top of the file. Frontmatter provides machine-readable metadata that Claude Code uses to discover, load, and describe the content.

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
| `model` | no | Model override (`inherit` uses parent model) |
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
| `description` | yes | What the skill does + trigger phrases — Claude Code uses this to decide when to invoke the skill |

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
- One instruction per line, indent sub-steps
- Use `-- comment` for context annotations
- Keep `OUTPUT` schemas explicit with named fields
- `NEVER`/`ALWAYS` rules are hard constraints the agent must not violate

## MCP Server Transport Types

Plugins use different MCP transport types in `.mcp.json`:
- **HTTP** — Remote server URL
- **npx** — Runs an npm package via `npx -y`
- **Local command** — Runs a local binary

## Adding a New Plugin

1. Determine the correct category directory
2. Create the plugin under `{category}/external_plugins/{plugin-name}/` (or `plugins/` for internal)
3. Add `.claude-plugin/plugin.json` with required metadata fields: `name`, `description`, `version`, `author`, `homepage`, `repository`
4. Add `.mcp.json` with the MCP server configuration
5. Add a `README.md` with plugin documentation
6. Register the plugin in `.claude-plugin/marketplace.json` under the `plugins` array, with the correct `source` path pointing to the plugin directory

### Marketplace Entry Fields

Each entry in `marketplace.json` supports these fields (in addition to `plugin.json` metadata):

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Plugin name (must match `plugin.json`) |
| `source` | yes | Relative path to the plugin directory (e.g., `./common/external_plugins/context7`) |
| `description` | yes | What the plugin does |
| `version` | yes | Semver version string |
| `author` | yes | Object with `name` field |
| `homepage` | no | URL to the plugin's homepage |
| `repository` | no | URL to the source repository |
| `keywords` | no | Array of strings for discovery/search |
| `category` | no | Marketplace category for grouping (e.g., `"Development Tools"`, `"Common"`) |
