---
name: recon
description: "Quick codebase reconnaissance. Use when the user says 'recon', 'explore this repo', 'what is this project', 'lay of the land', or '/recon'. Produces a structured overview of the current project."
---

# Recon

Quick interactive reconnaissance of the current project. Lighter than the full `scout` agent — gives you a fast overview without the deep dive.

## When to Use

- Dropping into an unfamiliar codebase for the first time
- Getting a refresher on a project you haven't touched in a while
- Orienting before starting a task in a new repo

## Workflow

### Step 1: Identify the project

Read the root directory and any manifest files (package.json, composer.json, pyproject.toml, Cargo.toml, go.mod). Check for README.md and CLAUDE.md.

### Step 2: Map the tech stack

From manifests and config files, identify:
- Languages and versions
- Frameworks
- Key dependencies
- CI/CD setup

### Step 3: Understand the architecture

Read the directory tree (2 levels deep). Identify the architectural pattern by checking against known patterns in `references/architecture-patterns.md`.

### Step 4: Find entry points

Locate route files, main entry points, CLI commands, and queue consumers.

### Step 5: Report

Present findings in this format:

```
RECON REPORT: {project-name}
==============================
Type:         {monorepo | service | library | cli}
Stack:        {languages} + {frameworks}
Architecture: {pattern}
Entry points: {count} ({types})

Key directories:
  src/        — {what's in it}
  tests/      — {what's in it}
  ...

Notable:
  - {anything interesting, unusual, or concerning}
```

## References

See `references/architecture-patterns.md` for the pattern catalog used during step 3.
