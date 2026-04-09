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

## Sudocode — Agent Convention

All agents in this marketplace **must** be written using sudocode — a pseudocode convention that replaces free-form prose with structured, scannable instructions. See [`docs/sudocode.md`](docs/sudocode.md) for the full specification and examples.

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
