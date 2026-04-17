# git-reset-on-clear

A Claude Code hook that automatically checks out `main` and pulls the latest code whenever you run `/clear`.

## What it does

When you run `/clear`, the `SessionStart` hook:

1. Stashes any uncommitted changes (if present)
2. Checks out `main` (falls back to `master`)
3. Pulls latest with `--ff-only`
4. Re-applies stashed changes

If the directory isn't a git repo, the hook silently exits.

## Installation

Add this to your `~/.claude/settings.json` (or project-level `.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "clear",
        "hooks": [
          {
            "type": "command",
            "command": "<path-to-plugin>/hooks/on-clear.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Make the script executable:

```bash
chmod +x hooks/on-clear.sh
```

## Plugin structure

```
git-reset-on-clear/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── on-clear.sh
└── README.md
```
