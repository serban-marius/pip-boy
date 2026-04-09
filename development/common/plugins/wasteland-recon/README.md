# Wasteland Recon

> *"Know your terrain before you set up camp."*

A codebase reconnaissance plugin with an agent and skill for exploring unfamiliar projects. Drop into any repo and get a structured lay-of-the-land report — tech stack, architecture patterns, entry points, and potential hazards.

## What's Included

### Agent: `scout`

A read-only recon agent that autonomously explores a codebase and produces a structured report. Written in [Sudocode](../../../../docs/sudocode.md). See [`agents/scout.md`](agents/scout.md).

### Skill: `recon`

A lighter, interactive version — invoke with `/recon` to get a quick overview of the current project. See [`skills/recon/SKILL.md`](skills/recon/SKILL.md).

### References

The `skills/recon/references/` directory contains companion docs the skill loads on demand:
- `architecture-patterns.md` — common patterns to look for during recon

## Usage

```
/recon                    # Quick interactive recon of current project
@scout explore this repo  # Full autonomous reconnaissance
```
