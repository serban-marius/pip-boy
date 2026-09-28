# overseer

A very light harness: Claude Code hooks that make an agent follow **spec → red test → green → commit → small PR**. It does not tell the agent how to work. It only refuses the steps that skip one.

| # | Rule | When | Effect |
|---|------|------|--------|
| 1 | The branch has a spec (`specs/*/spec.md` or `openspec/changes/*/`) | editing production code | block |
| 2 | A test was edited and then seen failing in this branch | editing production code | block |
| 3 | The last thing that happened was a green test run | `git commit` with code changes | block |
| 4 | A commit that changes production code also changes a test | after `git commit` | reminder |
| 5 | Each PR is the smallest piece that builds, passes its tests and is reviewable alone. Jev judges the cut; over ~400 prod lines against the PR base, the body must also say `Why not smaller: …` | `gh pr create` | block |
| 6 | The PR body names the spec path | `gh pr create` | block |
| 7 | An edit adds no prose comments to code or config (annotations, tool directives and one-line `ponytail:` shortcut markers are fine); the why goes in the PR as a review comment | after each edit | reminder |

## How it knows

It never learns your test command; it watches. A command that looks like a test runner (`phpunit`, `pest`, `artisan test`, `pytest`, `vitest`, `jest`, `go test`, `cargo test`, `npm test`…) and fails is **red**; one that succeeds is **green**. Every edit and run goes into a per-branch log at `.git/overseer/<branch>.log`, invisible to the repo.

Production code = a code file (`php js ts py go rs rb java kt swift c cs vue svelte`…) that is not a test and not under `specs/` or `openspec/`. Docs, config, JSON and YAML are always free.

## Hooks

| Event | `overseer.sh` subcommand |
|-------|--------------------------|
| `SessionStart` | `session`: prints `rules/overseer.md` |
| `PreToolUse` Edit/Write/MultiEdit | `pre-edit`: rules 1, 2 |
| `PostToolUse` Edit/Write/MultiEdit | `post-edit`: logs the edit, rule 7 |
| `PreToolUse` Bash | `pre-bash`: rules 3, 5, 6 |
| `PostToolUse` Bash | `post-bash`: logs a green run, rule 4 |
| `PostToolUseFailure` Bash | `bash-failed`: logs a red run |

Exit 0 is a silent pass. Exit 2 with a line starting `overseer:` blocks a Pre hook, or hands Claude a reminder from a Post hook.

## Known limits

- The test-runner list is a fixed regex. Add a runner when a repo needs one.
- Any failure of a test command counts as red, including "command not found".
- Red is required once per branch, not once per cycle, because refactoring on green is legitimate.
- Rule 5's cut is judged by Jev (TypeSafe AI) from the PR body, `git diff --numstat`, commit subjects and the diff itself, cut to fit 100k characters. The code leaves the machine for TypeSafe's API. It blocks only when Jev answers `splittable` with confidence ≥ 0.7, and it can only block more: with no key, a timeout (5 s) or low confidence, rule 5 falls back to the size question. The key comes from `OVERSEER_JEV_KEY` or the macOS keychain item `jev`.
- Rule 7 reads line comments and docblocks. Python docstrings are not detected, and a `ponytail:` marker must fit on one line (continuation lines count as prose).

## Escape hatch

`touch .git/overseer/off` turns every rule off for the repo; `rm` it to turn them back on. It is for humans only: hotfixes, spikes, carving a big PR into a stack. The rules forbid the agent from touching it.

## Not included, on purpose

- Human approval gates, review agents, EXPLAIN checks. Put them in a skill if you want them.
- A wall against an agent writing production files through Bash. The rules forbid it; the hooks do not police it.
- Model-judged checks (does the PR match the spec?). Candidate after pip-boy #25, warn-only.

Needs `bash`, `git`, `jq`, and `curl` plus a TypeSafe key for the Jev judge. Design: `docs/superpowers/specs/2026-09-28-overseer-design.md`.

## Development

```
hooks/overseer.test.sh   # throwaway git repo, fake hook JSON in, exit codes out
```
