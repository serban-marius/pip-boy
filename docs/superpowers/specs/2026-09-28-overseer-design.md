# overseer — design

A very light harness that **enforces** the delivery discipline (spec first, red first, green commits, small PRs that
point at their spec) through Claude Code hooks. It replaces the rules that used to live as prose in `tdd-workflow`:
no agent fleet, no human gates, no per-repo config. The agent works however it likes; there are just doors it cannot walk through.

## Goals

- An agent (interactive or unattended) cannot skip spec → red test → green → commit → small PR.
- Zero configuration per repo, and about zero tokens: everything is deduced from git and from what the agent runs.
- Stack-agnostic. Needs `bash`, `git`, `jq`.

## Non-goals

- Human approval gates, multi-agent review, EXPLAIN checks, automatic PR splitting (the hook says *split*; how is up to the agent/user).
- Hardening against an agent that writes production files through Bash (`cat > file`). The rule forbids it; the hook does not police it.
- Replacing CI.
- Model-judged checks (e.g. Jev, pip-boy #25) for what git can't decide: is the spec real, does the PR match it, is a
  test-less commit a refactor. Candidate after the #25 spike, on the slow cadences only (commit, PR), and only to warn or
  block more, never to unlock what a deterministic rule blocked.

## Rules

| # | Rule | Event | Effect |
|---|------|-------|--------|
| 1 | **Spec first**: the branch has touched a spec | `PreToolUse` Edit/Write/MultiEdit on a prod file | block |
| 2 | **Red first**: in this branch a test file was edited and a test run failed after that edit | `PreToolUse` Edit/Write/MultiEdit on a prod file | block |
| 3 | **Green commit**: the latest recorded event is a green test run; a test run chained into the commit command does not count | `PreToolUse` Bash `git commit` (only if the working tree has code changes, tracked or untracked) | block |
| 4 | **Commit carries a test**: a commit touching prod also touches a test | `PostToolUse` Bash `git commit` | warn (exit 2 after the fact; the commit stays) |
| 5 | **Smallest PR the feature allows**: cut by function, not size. Each PR is the smallest piece that builds, passes its tests and is reviewable alone. Over ~400 prod lines (added + deleted) vs the PR base, the body must carry `Why not smaller: …` | `PreToolUse` Bash `gh pr create` | block without the reason |
| 6 | **Ship**: the PR body mentions the spec path | `PreToolUse` Bash `gh pr create` | block |
| 7 | **No prose comments**: an edit adds no explanatory comment lines to code or config (`yaml yml toml sh bash Dockerfile Makefile` too). Annotations (`@…`), tool directives (`phpcs: eslint- noqa @ts- type: ignore shellcheck`…), attributes `#[…]`, shebangs, bare delimiters and one-line `ponytail:` markers (a deliberate shortcut: what it skips, its ceiling, the upgrade path) are allowed. Only added lines count (`git diff -U0 HEAD`, whole file when untracked). The why goes in the PR as a review comment on that line | `PostToolUse` Edit/Write/MultiEdit | warn (exit 2 after the edit) |

Block = exit 2 with a short reason on stderr (Claude sees it, the tool call does not happen). Silent on pass.

## Classification

- **Spec**: `specs/*/spec.md` (spec-kit) or anything under `openspec/changes/*/` (OpenSpec). A repo with neither
  uses the spec-kit layout without its tooling: `specs/NNN-slug/spec.md`.
- **Test file**: path contains `tests/`, `test/`, `__tests__/`, or a `spec/` dir (not `specs/`), or name matches
  `*Test.*`, `*_test.*`, `*.test.*`, `*.spec.*`, `test_*.py`.
- **Prod file**: a code extension (`php js jsx ts tsx mjs cjs py go rs rb java kt swift c cc cpp h cs vue svelte`) that is not a test file and not under `specs/`/`openspec/`.
  Everything else (markdown, config, JSON, YAML, lockfiles) is free.
- **Test run**: a Bash command matching `phpunit|pest|artisan test|pytest|vitest|jest|go test|cargo test|npm (run )?test|pnpm (run )?test|yarn test|bun test|rspec|mix test|gradle test|mvn test`.

## How it knows red from green

It never learns the test command; it watches. `PostToolUse(Bash)` fires only on success, `PostToolUseFailure(Bash)` only
on non-zero exit (verified against the hooks docs). A test-run command seen on the first is `green`, on the second `red`.

## State

Append-only log at `$(git rev-parse --git-dir)/overseer/<branch>.log`, one `epoch kind` line per event, with `kind` one of
`test-edit`, `prod-edit`, `red`, `green`. Per branch and per worktree, invisible to the repo, gone when `.git` is.

- Rule 2 passes when there is a `red` line after some `test-edit` line. Once per branch.
- Rule 3 passes when, among `test-edit|prod-edit|red|green`, the last line is `green`. No test re-run inside the hook, so committing is instant.

## Base branch

`origin/HEAD`'s target, falling back to `origin/main`, `origin/master`, then local `main`, `master` (repos with no remote). Rule 1 looks at
`git diff --name-only <base>...HEAD` plus `git status --porcelain` (staged, unstaged, untracked). A spec in a lower PR of a stack counts, because the diff is against the default branch.
Rule 5 uses the `--base`/`-B` value of the `gh pr create` command when present (stacked PRs), resolved as `origin/<x>`, then `<x>`.

## Rule 6 body

Body text = the `--body`/`-b` value in the command, or the contents of `--body-file`/`-F`. It must contain `specs/` or `openspec/changes/`.
`--fill` without a body gets blocked, which is intended.

## Escape hatch

`.git/overseer/off` (in `git rev-parse --git-common-dir`) disables every rule for the repo. The user creates and removes it by hand; the rule forbids the agent from touching it.
Known friction it covers: hotfixes without a spec, spikes, and carving a stack with `split-pr-stack` (new branches start with no `red` recorded).

## Known limits

- The test-runner list is a fixed regex; add a runner when a repo needs one.
- Any failure of a test command counts as red, including "command not found".
- Red is required once per branch, not once per cycle, because refactoring on green is legitimate.
- Rule 5 cannot judge whether a cut makes sense; size only decides when to ask. Next step: a Jev judge (pip-boy #25) asked "could this PR split into smaller pieces that each build, pass tests and review alone?" over the spec, `git diff --stat` and commit subjects (no code). It only blocks more; with no key, a timeout or low confidence it falls back to the size ask. Benchmark: toucan #101 (should be splittable) and its 14-phase stack #103–#117 (should be indivisible).
- Rule 7 reads line comments and docblocks; Python docstrings are not detected, and a `ponytail:` marker must fit on one line.
- The script and its self-check follow rule 7 themselves: no prose comments, only `ponytail:` markers on the shortcuts above.

## Getting the rules into context

A `SessionStart` hook prints `rules/overseer.md` (about 30 lines): the cycle, what each block means and how to clear it,
four lines on writing minimal code (does it need to exist; reuse, then stdlib, then platform; shortest diff once the problem is understood; fix the cause), and
"when a hook blocks you, fix the cause; never write a file through Bash to get around it, never touch `.git/overseer/`".
Repos that are not git repos are left alone (every hook exits 0).

## Layout

```
development/common/plugins/overseer/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json          # SessionStart, PreToolUse(Edit|Write|MultiEdit, Bash), PostToolUse(Edit|Write|MultiEdit, Bash), PostToolUseFailure(Bash)
│   ├── overseer.sh         # one script, subcommand per event
│   └── overseer.test.sh    # fake hook JSON in a temp git repo, asserts exit codes
├── rules/overseer.md
└── README.md
```

Registered in `.claude-plugin/marketplace.json` as `overseer` 0.1.0, category "Development Tools".

## Testing

`overseer.test.sh` builds a throwaway git repo and drives the script with fake hook JSON, one scenario per rule, pass and block:
prod edit with no spec blocks; with spec but no red blocks; test-edit → red unlocks; commit after a prod-edit with no later green
blocks; green unblocks; a 401-line prod diff blocks `gh pr create`; a body without a spec path blocks; `off` lets everything through; outside a git repo everything passes.
