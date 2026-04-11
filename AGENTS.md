# AGENTS.md

## Critical Rules

- **ALWAYS register new plugins in `.claude-plugin/marketplace.json`** — unlisted plugins don't exist to the marketplace
- **ALWAYS include YAML frontmatter** in `agents/*.md`, `skills/*/SKILL.md`, and `rules/*.md` — without it, Claude Code won't discover them

## No Build System

This is a **configuration repository only** — no build, no tests, no dependencies. The only verification needed is that files are syntactically valid JSON/YAML/markdown.

## Adding a Plugin

1. Pick category (`common/`, `development/*/`, etc.)
2. Create `{category}/external_plugins/{name}/` (or `plugins/` for internal)
3. Add `.claude-plugin/plugin.json` (required) — fields: `name`, `description`, `version`, `author`, `homepage`, `repository`
4. Add `.mcp.json` (optional) — MCP server config
5. Add `README.md` (required)
6. **Register in `.claude-plugin/marketplace.json`** — add entry to `plugins` array with `name`, `source`, `description`, `version`, `author`

## Agent Format

Agents use **Sudocode** (pseudocode with keywords: `DO`, `READ`, `GATHER`, `CLASSIFY`, `NEVER`, `ALWAYS`). See `docs/sudocode.md` for spec.

## Directory Structure

```
category/                    # e.g., common/, development/js/
├── plugins/                 # Internal plugins
│   └── plugin-name/
│       ├── .claude-plugin/plugin.json
│       ├── .mcp.json (optional)
│       ├── README.md
│       ├── agents/ (optional)
│       ├── skills/ (optional)
│       └── rules/ (optional)
└── external_plugins/        # Third-party plugins (same structure)
```

## Reference

- Full docs: `README.md`, `CLAUDE.md`, `docs/sudocode.md`