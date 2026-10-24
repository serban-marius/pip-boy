# git-reset-on-clear

A Claude Code hook that, on `/clear`, returns a clean checkout to the default branch and fast-forwards it.

## What it does

On `SessionStart` with matcher `clear`, the hook:

- does nothing outside a git repository
- leaves the tree alone, with a one-line notice, when there are uncommitted tracked changes — it never stashes and never switches
- leaves a linked worktree on its branch
- leaves a detached HEAD alone
- on a clean checkout on a non-default branch, checks out the default branch (`origin/HEAD`, else `main`, else `master`)
- on the default branch, runs `git pull --ff-only`
- always exits 0 and prints one short line saying what it did

## Installation

Enable the plugin from the marketplace:

```
/plugin marketplace add serban-marius/pip-boy
/plugin install git-reset-on-clear@pip-boy
```

The plugin ships its own `hooks/hooks.json`; no settings edit or `chmod` is needed.

## Interaction with other plugins

The hook never touches linked worktrees, so [mister-handy](../../../development/common/plugins/mister-handy/README.md) workers keep their branches and [overseer](../../../development/common/plugins/overseer/README.md) keeps its per-branch logs.

A clean main checkout sitting on a feature branch is still switched to the default branch on `/clear`. That is the remaining overlap with foreman and with per-branch logs written in the shared checkout: run agent work in a linked worktree, or commit before clearing.

## Plugin structure

```
git-reset-on-clear/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json
│   ├── on-clear.sh
│   └── on-clear.test.sh
└── README.md
```

## Tests

```bash
bash common/plugins/git-reset-on-clear/hooks/on-clear.test.sh
```
