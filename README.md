# Pip-Boy 3000 Mark IV — Plugin Registry

> *"War. War never changes. But your dev tooling should."*

A personal curated collection of Claude Code plugins. Each plugin is a module you slot into your Pip-Boy to gain new capabilities.

> **Warning:** Make sure you trust a plugin before installing. Anthropic does not control what MCP servers, files, or other software are included in plugins. Check each plugin's homepage before use.

## Structure

Plugins are organized by category, each with `plugins/` (internal) and `external_plugins/` (third-party) directories:

| Section | Contents |
|---------|----------|
| **`/common`** | General-purpose plugins for any project |
| **`/development/common`** | Language-agnostic dev tools |
| **`/development/js`** | JavaScript/TypeScript ecosystem |
| **`/development/php`** | PHP ecosystem |
| **`/development/python`** | Python ecosystem |
| **`/infrastructure`** | Infrastructure & SRE plugins |
| **`/seo`** | SEO and search tools |
| **`/bi`** | Business Intelligence & analytics |
| **`/product`** | Product management & design |

## Installation

Add the marketplace:

```
/plugin marketplace add git@github.com:serban-marius/pip-boy.git
```

Or add to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "pip-boy": {
      "source": {
        "source": "git",
        "url": "git@github.com:serban-marius/pip-boy.git"
      }
    }
  },
  "enabledPlugins": {
    "plugin-name@pip-boy": true
  }
}
```

Install individual plugins with `/plugin install {plugin-name}@pip-boy`, or browse via `/plugin > Discover`.

## Adding a Plugin

### External (third-party)

1. Pick the right category (e.g., `common/`, `development/js/`)
2. Create `{category}/external_plugins/{plugin-name}/`
3. Add `.claude-plugin/plugin.json` with metadata
4. Add `.mcp.json` with MCP server configuration
5. Add `README.md` with documentation
6. Register in `.claude-plugin/marketplace.json` — or it doesn't exist

### Internal

Same steps, but under `{category}/plugins/{plugin-name}/`.

## Plugin Anatomy

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata (required)
├── .mcp.json                # MCP server configuration (optional)
├── commands/                # Slash commands (optional)
├── agents/                  # Agent definitions (optional) — frontmatter + Sudocode
├── skills/
│   └── skill-name/
│       ├── SKILL.md         # Skill definition — frontmatter + markdown
│       ├── references/      # Companion docs loaded on demand
│       └── bin/             # Executable scripts the skill invokes
├── rules/                   # Convention files (optional) — frontmatter + markdown
└── README.md                # Plugin documentation
```

### YAML Frontmatter

Every `.md` content file (agents, skills, rules) starts with YAML frontmatter — the `---` delimited block at the top. It's how Claude Code identifies and catalogs each piece. No frontmatter, no discovery.

**Agent** (`agents/*.md`):
```yaml
---
name: recon-bot
description: Scouts the codebase for security vulnerabilities
tools: Read, Bash, Grep, Glob
model: inherit
skills: recon, threat-assess
---
```

**Skill** (`skills/*/SKILL.md`):
```yaml
---
name: lockpick
description: "Crack open legacy code. Use when user says 'refactor', 'untangle', or '/lockpick'."
---
```

**Rule** (`rules/*.md`):
```yaml
---
name: api-response-convention
description: Convention for structuring API response handlers
---
```

## Sudocode — Agent Definition Language

All agents are written in **Sudocode** — a pseudocode convention that replaces free-form prose with structured, scannable instructions. Think of it as the programming language running on your Pip-Boy's OS.

Instead of dumping a wall of text and hoping the AI figures it out, Sudocode uses explicit keywords:

| Keyword | What it does |
|---------|-------------|
| `DO` | Execute an action |
| `READ` | Read a file, API, or data source |
| `GATHER` | Collect data from multiple sources |
| `CLASSIFY` | Make a judgment call |
| `NEVER` | Hard constraint — do not violate |
| `ALWAYS` | Mandatory behavior |
| `PREFER...OVER` | Soft preference |
| `IF...THEN...ELSE` | Conditional logic |
| `FOR EACH...IN` | Iteration |
| `OUTPUT` | Produce structured results |
| `ON FAILURE` | Graceful degradation |

Example (frontmatter + sudocode):

```yaml
---
name: dependency-auditor
description: Audits project dependencies for security issues, license conflicts, and staleness
tools: Read, Bash, Grep, Glob, WebFetch
model: inherit
---

AGENT: dependency-auditor
ROLE: audit project dependencies for security, licensing, and freshness
PERSONA: thorough but concise security reviewer

RULES:
  NEVER install or modify packages — read-only
  ALWAYS check both direct and transitive dependencies
  PREFER official advisory databases OVER blog posts

WHEN invoked:
  1. READ package manifest
  2. DO `npm audit` or equivalent for detected ecosystem
  3. GATHER $advisories FROM GitHub Advisory Database
  4. FOR EACH $dep IN dependencies:
       CLASSIFY $dep AS up-to-date | outdated | abandoned | vulnerable
  5. IF license is copyleft THEN
       EMIT warning: "copyleft license detected"

OUTPUT audit-report:
  summary: one-paragraph health assessment
  critical: CVEs requiring immediate action
  outdated: deps more than 2 major versions behind
  recommendations: prioritized action items

ON FAILURE:
  IF registry unreachable THEN skip, note in output
  NEVER block on a single failure
```

Full spec: [`docs/sudocode.md`](docs/sudocode.md)

## Documentation

See the [official plugin docs](https://code.claude.com/docs/en/plugins) for more.

---

*"Another settlement needs your help. I've marked it on your map."*
*— This README, every time you forget to register a plugin in marketplace.json*
