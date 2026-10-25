# AGENTS.md

The one short source of repo-wide truth: what this repo is, how a plugin is shaped, how to test, and what not to touch. Claude-specific conventions live in `CLAUDE.md`, which imports this file.

## What This Repo Is

A **Claude Code plugin marketplace**: a curated registry of plugins maintained as configuration, docs, and shell/Python scripts. Nothing is compiled or packaged. The runtime dependencies are `bash` and `python3`; some plugin scripts also call `git`, `gh`, `jq`, `deno`, or `npm`.

## Repository Structure

Plugins are organized by **category**. Each category contains:

- `plugins/` — Internal plugins maintained by the owner
- `external_plugins/` — Third-party plugins

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
| `automation/` | Skills built to run unattended: scheduled agents, watchers, OpenClaw automations |

`.claude-plugin/marketplace.json` is the central manifest. Every plugin must be registered there.

## Plugin Anatomy

```text
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # Required metadata
├── .mcp.json            # Optional MCP server configuration
├── README.md            # Required plugin documentation
├── commands/            # Optional slash commands
├── agents/              # Optional agent definitions
├── skills/
│   └── skill-name/
│       ├── SKILL.md     # Skill definition
│       ├── references/  # Optional docs loaded on demand
│       ├── bin/         # Optional executable scripts
│       └── evals/       # Optional skill evals
├── rules/               # Optional convention files
└── hooks/               # Optional lifecycle hooks
```

Plugins may also carry their own script directories, such as `guardrails/` in `github-janitor`.

Plugin metadata (`plugin.json`) uses `name`, `description`, `version`, `author`, `homepage`, and `repository`. When present, `.mcp.json` can start an MCP server over an HTTP URL, an `npx` package, or a local command.

## Adding a Plugin

1. Pick the correct category directory.
2. Create `{category}/external_plugins/{name}/` for third-party plugins, or `{category}/plugins/{name}/` for internal ones.
3. Add `.claude-plugin/plugin.json` with the metadata fields above.
4. Add `.mcp.json` only if the plugin ships an MCP server.
5. Add `README.md` documenting the plugin.
6. Register the plugin in `.claude-plugin/marketplace.json`.

### Marketplace Entry Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Plugin name (must match `plugin.json`) |
| `source` | yes | Relative path to the plugin directory, e.g. `./common/external_plugins/context7` |
| `description` | yes | What the plugin does |
| `version` | yes | Semver version string (must match `plugin.json`) |
| `author` | yes | Object with a `name` field |
| `homepage` | no | URL to the plugin's homepage |
| `repository` | no | URL to the source repository |
| `keywords` | no | Array of strings for discovery/search |
| `category` | no | Marketplace category for grouping |

## Versioning and Commits

- A plugin change bumps the version in its `plugin.json` **and** in its `.claude-plugin/marketplace.json` entry — both together.
- Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`.
- A plugin change ends the commit/PR title with the new version, e.g. `fix(git-reset-on-clear): ... (1.1.0)`.

## Testing

Every suite is no-arg; run these from the repo root before opening a PR:

```bash
bash development/common/plugins/overseer/hooks/overseer.test.sh
bash development/common/plugins/vats/hooks/vats.test.sh
python3 development/common/plugins/holotape/skills/jira-write/bin/test_jira_preview.py
PATH="$PWD/automation/plugins/github-janitor/guardrails:$PATH" bash automation/plugins/github-janitor/guardrails/test-shims.sh
```

The delegate suite is slower (a few minutes):

```bash
bash development/common/plugins/mister-handy/skills/delegate/bin/delegate.test.sh
```

Evals live next to the skill that owns them; currently `automation/plugins/github-janitor/skills/pr-address-comments/evals/evals.json`.

CI (`.github/workflows/ci.yml`) runs these suites plus `bash scripts/check-marketplace.sh` on every PR. `check-marketplace.sh` validates JSON, checks that `marketplace.json` and each `plugin.json` agree on name and version, and fails on unregistered plugin directories.

## What Not to Touch

- Never leave a plugin unregistered: an entry missing from `.claude-plugin/marketplace.json` does not exist to the marketplace.
- `agents/*.md` use sudocode and, like `skills/*/SKILL.md` and `rules/*.md`, need YAML frontmatter or they are not discovered; details are in `CLAUDE.md` and `docs/sudocode.md`.
- When bumping a version, touch only that plugin's `plugin.json` and its own `marketplace.json` entry.

## Reference

- Human-facing overview and install instructions: `README.md`
- Claude-specific conventions: `CLAUDE.md`
- Sudocode spec: `docs/sudocode.md`
