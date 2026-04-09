# Pip-Boy 3000 Mark IV — Plugin Registry

> *"War. War never changes. But your dev tooling should."*

A personal Vault-Tec approved collection of Claude Code plugins. Each plugin is a module you slot into your Pip-Boy to gain new capabilities — like finding a Stealth Boy in an abandoned vault, except it actually works and doesn't expire after 30 seconds.

> **Radiation Warning:** Make sure you trust a plugin before installing. Anthropic does not control what MCP servers, files, or other software are included in plugins. Some things in the Wasteland look like Stimpaks but are actually Radscorpion venom. Check each plugin's homepage before use.

## Vault Layout

Plugins are organized into sections of the Vault, each with its own `plugins/` (Vault-Tec issued) and `external_plugins/` (scavenged from the Wasteland) directories:

| Section | Contents | S.P.E.C.I.A.L. Stat |
|---------|----------|---------------------|
| **`/common`** | General-purpose plugins for any project | Luck |
| **`/development/common`** | Language-agnostic dev tools | Intelligence |
| **`/development/js`** | JavaScript/TypeScript ecosystem | Agility |
| **`/development/php`** | PHP ecosystem | Endurance |
| **`/development/python`** | Python ecosystem | Perception |
| **`/infrastructure`** | Infrastructure & SRE plugins | Strength |
| **`/seo`** | SEO and search tools | Charisma |
| **`/bi`** | Business Intelligence & analytics | Perception |
| **`/product`** | Product management & design | Charisma |

## Installation — Leaving the Vault

Add the marketplace to your Pip-Boy:

```
/plugin marketplace add git@github.com:serban-marius/pip-boy.git
```

Or hardwire it into `.claude/settings.json` like a true Wasteland engineer:

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

Install individual modules with `/plugin install {plugin-name}@pip-boy`, or browse the catalog via `/plugin > Discover`.

## Crafting a New Module

*"In the Wasteland, you don't buy — you build."*

### Scavenged Module (third-party)

1. Find the right Vault section (e.g., `common/`, `development/js/`)
2. Create `{section}/external_plugins/{module-name}/`
3. Add `.claude-plugin/plugin.json` — your module's serial number
4. Add `.mcp.json` — the wiring diagram
5. Add `README.md` — because even Raiders leave notes
6. Register in `.claude-plugin/marketplace.json` — or it doesn't exist

### Vault-Tec Issued Module (internal)

Same steps, but under `{section}/plugins/{module-name}/`. Quality assured. Probably.

## Module Anatomy

```
module-name/
├── .claude-plugin/
│   └── plugin.json      # Module serial number (required)
├── .mcp.json            # MCP wiring diagram (optional)
├── commands/            # Slash commands (optional)
├── agents/              # Agent holotapes (optional) — frontmatter + Sudocode
├── skills/              # Skill modules (optional) — frontmatter + markdown
├── rules/               # Convention files (optional) — frontmatter + markdown
└── README.md            # Wasteland survival guide
```

### YAML Frontmatter — The Module's Dog Tags

Every `.md` content file (agents, skills, rules) starts with YAML frontmatter — the `---` delimited block at the top. It's how your Pip-Boy identifies and catalogs each piece of tech. No dog tags, no service.

**Agent holotape** (`agents/*.md`):
```yaml
---
name: recon-bot
description: Scouts the codebase for security vulnerabilities
tools: Read, Bash, Grep, Glob
model: inherit
---
```

**Skill module** (`skills/*/SKILL.md`):
```yaml
---
name: lockpick
description: "Crack open legacy code. Use when user says 'refactor', 'untangle', or '/lockpick'."
---
```

**Rule file** (`rules/*.md`):
```yaml
---
name: power-armor-protocol
description: Convention for structuring API response handlers
---
```

Without frontmatter, your module is just a note on a corpse. With it, it's a functioning piece of pre-war technology.

## Sudocode — Agent Programming Language

> *"Knowledge of the old world is the most valuable currency in the new."*

All agents in this registry are written in **Sudocode** — a pseudocode convention that replaces free-form prose with structured, scannable instructions. Think of it as the programming language running on your Pip-Boy's OS.

Instead of dumping a wall of text and hoping the AI figures it out (the Bethesda approach to QA), Sudocode uses explicit keywords:

| Keyword | What it does |
|---------|-------------|
| `DO` | Execute an action |
| `READ` | Read a file, API, or data source |
| `GATHER` | Collect data from multiple sources |
| `CLASSIFY` | Make a judgment call |
| `NEVER` | Hard constraint — violating this is like drinking from a toilet in Megaton |
| `ALWAYS` | Mandatory behavior |
| `PREFER...OVER` | Soft preference |
| `IF...THEN...ELSE` | Conditional logic |
| `FOR EACH...IN` | Iteration |
| `OUTPUT` | Produce structured results |
| `ON FAILURE` | Graceful degradation — because nothing works first try in the Wasteland |

Example — an agent holotape (frontmatter + sudocode):

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

## S.P.E.C.I.A.L. Stats

- **S**tructure — Clean category-based organization
- **P**lugins — MCP servers, skills, agents, commands
- **E**xtensible — Add new categories anytime
- **C**urated — Only stuff that actually works
- **I**ndependent — Each plugin is self-contained
- **A**gents — Written in Sudocode, not essays
- **L**ightweight — No build system, no deps, no BS

## Documentation

See the [official plugin docs](https://code.claude.com/docs/en/plugins) for more information.

Or don't. The Wasteland rewards the self-taught.

---

*"Another settlement needs your help. I've marked it on your map."*
*— This README, every time you forget to register a plugin in marketplace.json*
