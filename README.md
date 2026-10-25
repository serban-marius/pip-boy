# Pip-Boy 3000 Mark IV — Plugin Registry

> *"War. War never changes. But your dev tooling should."*

A personal curated collection of Claude Code plugins. Each plugin is a module you slot into your Pip-Boy to gain new capabilities.

> **Warning:** Make sure you trust a plugin before installing. Anthropic does not control what MCP servers, files, or other software is included in plugins. Check each plugin's homepage before use.

## Catalog

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
| **`/automation`** | Skills for unattended agents & OpenClaw automations |

The full list of installable plugins lives in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

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

## Contributing

Plugin anatomy, the steps for adding a plugin, marketplace entry fields, versioning, and how to run the test suites are documented once in [AGENTS.md](AGENTS.md). Read that before opening a PR. Commit conventions and review requirements are in [CONTRIBUTING.md](CONTRIBUTING.md).

Agent-specific conventions, including YAML frontmatter and sudocode, are in [CLAUDE.md](CLAUDE.md).

## Documentation

See the [official plugin docs](https://code.claude.com/docs/en/plugins) for more.

---

*"Another settlement needs your help. I've marked it on your map."*
*— This README, every time you forget to register a plugin in marketplace.json*
