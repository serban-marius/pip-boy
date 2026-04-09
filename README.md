# Claude Code Plugins

A personal curated directory of plugins for Claude Code.

> **Warning:** Make sure you trust a plugin before installing, updating, or using it. Anthropic does not control what MCP servers, files, or other software are included in plugins and cannot verify that they will work as intended or that they won't change. See each plugin's homepage for more information.

## Structure

Plugins are organized by category, each with its own `plugins/` (internal) and `external_plugins/` (third-party) directories:

- **`/common`** - General-purpose plugins useful across all projects
- **`/development`** - Development-focused plugins, with subcategories:
  - **`/development/common`** - Language-agnostic development tools
  - **`/development/js`** - JavaScript/TypeScript ecosystem plugins
  - **`/development/php`** - PHP ecosystem plugins
  - **`/development/python`** - Python ecosystem plugins
- **`/infrastructure`** - Infrastructure and SRE plugins
- **`/seo`** - SEO and search-related plugins
- **`/bi`** - Business Intelligence and analytics plugins
- **`/product`** - Product management and design plugins

## Installation

Add the marketplace:

```
/plugin marketplace add <your-git-url>
```

Or add to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "my-plugins": {
      "source": {
        "source": "git",
        "url": "<your-git-url>"
      }
    }
  },
  "enabledPlugins": {
    "plugin-name@ai-plugins": true
  }
}
```

Install individual plugins with `/plugin install {plugin-name}@ai-plugins`, or browse via `/plugin > Discover`.

## Adding a Plugin

### External Plugin (third-party)

1. Pick the right category directory (e.g., `common/`, `development/js/`)
2. Create `{category}/external_plugins/{plugin-name}/`
3. Add `.claude-plugin/plugin.json` with metadata
4. Add `.mcp.json` with MCP server configuration
5. Add `README.md` with documentation
6. Register in `.claude-plugin/marketplace.json`

### Internal Plugin

Same steps, but under `{category}/plugins/{plugin-name}/`.

## Plugin Structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata (required)
├── .mcp.json            # MCP server configuration (optional)
├── commands/            # Slash commands (optional)
├── agents/              # Agent definitions (optional)
├── skills/              # Skill definitions (optional)
├── rules/               # Rule files (optional)
└── README.md            # Documentation
```

## Documentation

See the [official plugin docs](https://code.claude.com/docs/en/plugins) for more information.
