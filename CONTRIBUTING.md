# Contributing

Thanks for your interest in contributing to this plugin marketplace.

## How to Contribute

1. Fork the repository
2. Create a branch from `main` (`chore/my-change`, `feat/new-plugin`, etc.)
3. Make your changes following the conventions below
4. Open a pull request — 2 approvals from code owners are required to merge

## Adding a Plugin

See [CLAUDE.md](CLAUDE.md) for the full plugin anatomy and registration steps. In short:

1. Choose the correct category directory
2. Create the plugin structure (`.claude-plugin/plugin.json`, `.mcp.json`, `README.md`)
3. Register the plugin in `.claude-plugin/marketplace.json`

## Conventions

- **Commits**: use [conventional commits](https://www.conventionalcommits.org/) — `type(scope): description`
  - Types: `feat`, `fix`, `refactor`, `test`, `style`, `docs`, `chore`
  - Scope is optional but encouraged (e.g., `feat(marketplace): add new plugin`)
  - PR titles must also follow this format
- **Agents**: must use [sudocode](docs/sudocode.md) and include YAML frontmatter
- **Skills & Rules**: must include YAML frontmatter (see [CLAUDE.md](CLAUDE.md))
- **Branch names**: `type/short-description` (e.g., `feat/add-new-plugin`)

## Questions?

Open an issue or reach out to a code owner.
