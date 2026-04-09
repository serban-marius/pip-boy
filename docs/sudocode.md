# Sudocode — Agent Definition Language

Sudocode is a pseudocode convention for writing Claude Code agents. It replaces free-form prose with a structured, readable format that's easy to write, scan, and maintain.

## File Format

Agent files are `.md` files with two parts:

1. **YAML frontmatter** (required) — machine-readable metadata between `---` delimiters
2. **Sudocode body** — the agent's instructions in pseudocode syntax

```markdown
---
name: agent-name
description: What this agent does and when to invoke it
tools: Read, Bash, Grep, Glob, WebFetch
model: inherit
---

AGENT: agent-name
ROLE: ...
(sudocode body)
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Kebab-case identifier, matches the filename |
| `description` | yes | What the agent does — Claude Code uses this for discovery and routing |
| `tools` | yes | Comma-separated list of tools the agent can access |
| `model` | no | Model override (`inherit` = use parent model) |
| `skills` | no | Comma-separated list of skills the agent can load on demand |

The frontmatter is for Claude Code's runtime. The sudocode body is for the agent's brain. Don't duplicate info between them — `name` and `description` in frontmatter are enough; the sudocode `AGENT:` and `ROLE:` lines provide the agent's self-understanding and can be more expressive.

## Syntax

### Block Structure

```
AGENT: agent-name
ROLE: one-line description of what this agent does
PERSONA: optional tone/personality (e.g., "terse SRE oncall", "patient teacher")

RULES:
  NEVER do dangerous thing
  ALWAYS do safe thing
  PREFER X OVER Y

WHEN invoked:
  1. DO action description
  2. READ source/file/api
  3. IF condition THEN
       DO this
     ELSE
       DO that
  4. FOR EACH item IN collection:
       DO something with item
  5. GATHER data FROM source
  6. CLASSIFY result AS category

OUTPUT format-name:
  field: description
  field: description

ON FAILURE:
  IF step fails THEN skip, note in output
  NEVER block on a single failure
```

### Keywords

| Keyword | Meaning |
|---------|---------|
| `DO` | Execute an action (bash command, tool call, reasoning step) |
| `READ` | Read a file, API, or data source |
| `GATHER` | Collect data from multiple sources |
| `CLASSIFY` | Make a judgment/categorization based on data |
| `OUTPUT` | Produce structured output |
| `IF...THEN...ELSE` | Conditional logic |
| `FOR EACH...IN` | Iteration |
| `WHEN` | Trigger/entry point |
| `NEVER` | Hard constraint (agent must not violate) |
| `ALWAYS` | Mandatory behavior |
| `PREFER...OVER` | Soft preference |
| `ASK` | Prompt the user for input |
| `WAIT FOR` | Block until a condition is met |
| `RETRY` | Attempt again with modified approach |
| `EMIT` | Produce a side output (log, notification) |
| `DELEGATE TO` | Hand off to another agent or skill |

### Inline Code

Wrap concrete commands or queries in backticks within a `DO` or `READ`:

```
DO `git log --oneline -20`
READ `curl -s https://api.example.com/status`
```

### Variables

Use `$name` for dynamic values:

```
GATHER $errors FROM error-log
FOR EACH $error IN $errors:
  CLASSIFY $error AS critical | warning | noise
```

### Annotations

Use `-- comment` for inline context that helps the agent but isn't an instruction:

```
DO check TLS fingerprint  -- see ONCALL-816 for why this matters
NEVER hard-block browser fingerprints  -- causes mass false positives
```

## Example Agent

```markdown
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
  NEVER ignore critical CVEs
  ALWAYS check both direct and transitive dependencies
  PREFER official advisory databases OVER blog posts

WHEN invoked:
  1. READ package manifest  -- package.json, composer.json, requirements.txt, Cargo.toml
  2. DO `npm audit` or equivalent for detected ecosystem
  3. GATHER $advisories FROM GitHub Advisory Database via WebFetch
  4. FOR EACH $dep IN dependencies:
       READ latest version from registry
       CLASSIFY $dep AS up-to-date | outdated | abandoned | vulnerable
  5. READ license file for each dependency
     IF license is copyleft (GPL, AGPL) THEN
       EMIT warning: "copyleft license may conflict with project license"
  6. CLASSIFY overall health AS healthy | needs-attention | critical

OUTPUT audit-report:
  summary: one-paragraph health assessment
  critical: list of CVEs requiring immediate action
  outdated: list of deps more than 2 major versions behind
  license-flags: list of license conflicts or unknowns
  recommendations: prioritized action items

ON FAILURE:
  IF registry unreachable THEN note in report, continue with local data
  IF no lockfile found THEN warn user, audit manifest only
```

## Writing Tips

- **One instruction per line.** If a step has sub-steps, indent them.
- **Be specific in NEVER/ALWAYS rules.** "NEVER delete files" is better than "be careful."
- **Use CLASSIFY for judgment calls.** It signals the agent needs to reason, not just execute.
- **Keep OUTPUT schemas tight.** Name the fields the agent should produce.
- **Annotations are free.** Use `-- comment` to explain *why*, not *what*.
- **Don't over-specify.** Sudocode guides the agent's reasoning — it's not a script to execute line by line. Leave room for the agent to adapt.
