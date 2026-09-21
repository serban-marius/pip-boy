# vats

**V.A.T.S. (Verifiers At Tiered Stages)**: cheap, frequent verifiers wired into a repo as Claude Code hooks, each at its own cadence. The agent gets its own failures back and fixes them before a human ever looks.

> Human attention costs more than tokens. You can't align what you can't verify.

| Cadence | What runs | How |
|---|---|---|
| every edit | lint, types, antipatterns, on the one file | `PostToolUse` hook |
| every `git commit` | tests, contracts | `PreToolUse(Bash)` hook, blocks the commit on red |
| release | integration, E2E | your CI, not this plugin |
| now and then | mutation testing of a sensitive module | `/vats mutate <path>` |

## Usage

In the repo you want to harness:

```
/vats
```

The skill detects the stack, picks the fast per-file commands **the repo already has** (it never installs anything), times them, writes `.claude/hooks/vats.sh`, merges two hook entries into `.claude/settings.json`, and proves the hook works by watching it fail on a deliberately broken file and pass again. Restart the session afterwards so the hooks load.

```
/vats mutate app/Billing
```

Runs the stack's mutation tester (Infection, Stryker, mutmut, PIT, cargo-mutants) filtered to that path and reports the surviving mutants: the code changes no test noticed.

## What lands in your repo

```
.claude/
├── hooks/vats.sh      # ~50 lines; you own the two functions: on_edit and on_commit
└── settings.json      # two hook entries
```

Both are meant to be committed: teammates get the verifiers without installing this plugin, and the hooks go through Claude Code's normal trust flow. `vats.sh` needs `jq`.

The contract is small: a check that passes prints nothing; a check that fails exits 2 with the last 40 lines on stderr. On an edit, Claude receives that as a reminder and fixes the file; on a commit, the commit is blocked until the tests are green.

**From incident to rule:** when the agent makes a new class of mistake, add the cheapest check that would have caught it to `on_edit` or `on_commit`. A `grep` for a banned pattern is a perfectly good verifier.

## Not included, on purpose

- An LLM judge on every edit, for rules a linter can't express. See [lsp-smell](https://github.com/double-thinker/lsp-smell).
- Release-cadence checks. They belong to CI.

## Development

```
skills/vats/templates/vats.test.sh   # self-check for the hook script: fake hook JSON in, exit codes out
```

## Plugin structure

```
vats/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── vats/
│       ├── SKILL.md
│       └── templates/
│           ├── vats.sh
│           └── vats.test.sh
└── README.md
```
