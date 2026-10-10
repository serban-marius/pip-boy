# overseer

A very light harness: Claude Code hooks that make an agent follow **spec → red test → green → commit → small PR**. It does not tell the agent how to work. It only refuses the steps that skip one.

| # | Rule | When | Effect |
|---|------|------|--------|
| 1 | The branch has a spec (`specs/*/spec.md` or `openspec/changes/*/`), or a commit that says `Spec impact: None — <why>` | editing production code | block |
| 2 | A test was edited and then seen failing in this branch | editing production code | block |
| 3 | The last thing that happened was a green test run | `git commit` with code changes | block |
| 4 | A commit that changes production code also changes a test | after `git commit` | reminder |
| 5 | Each PR is the smallest piece that builds, passes its tests and is reviewable alone. A PR against the default branch with over ~400 prod lines goes through `split-pr-stack` (caravan) or says `Why not smaller: …`; stacked PRs are trusted | `gh pr create` | block |
| 6 | The PR body names the spec path, or `Spec impact: None — <why>` | `gh pr create` | block |
| 7 | Names explain the code: no prose comments in code or config. Bare type annotations (`@param list<Item> $items`, `@return array{0: int}`), tool directives, attributes, bare markers (`@deprecated`) and one-line `ponytail:` shortcut markers are fine; an annotation with text after it, `@see` or `@todo` is prose. The why goes in the PR as a review comment, and after `gh pr create` the hook lists the files whose comments were stripped | after each edit, after `gh pr create` / `git commit` | reminder / block |
| 8 | Small functions, small files: in production code every function an edit touches has at most 15 body lines, nesting 2 and 4 parameters (constructors exempt), and a file that defines functions at most 200 code lines (data-only files are free). Blank and comment lines do not count; tests are exempt | after each edit / `git commit` | reminder / block |

## How it knows

It never learns your test command; it watches. A command that looks like a test runner (`phpunit`, `pest`, `artisan test`, `pytest`, `vitest`, `jest`, `go test`, `cargo test`, `npm test`, `deno test`…) and fails is **red**; one that succeeds is **green**. Every edit and run goes into a per-branch log at `.git/overseer/<branch>.log`, invisible to the repo.

Production code = a code file (`php js ts py go rs rb java kt swift c cs vue svelte`…) that is not a test and not under `specs/` or `openspec/`. Docs, config, JSON and YAML are always free.

## Hooks

| Event | `overseer.sh` subcommand |
|-------|--------------------------|
| `SessionStart` | `session`: prints `rules/overseer.md` |
| `PreToolUse` Edit/Write/MultiEdit | `pre-edit`: rules 1, 2 |
| `PostToolUse` Edit/Write/MultiEdit | `post-edit`: logs the edit, rules 7 and 8 |
| `PreToolUse` Bash | `pre-bash`: rules 3, 5, 6, 7 and 8 (commit) |
| `PostToolUse` Bash | `post-bash`: logs a green run, rules 4 and 7 (the why-comments reminder) |
| `PostToolUseFailure` Bash | `bash-failed`: logs a red run |

Exit 0 is a silent pass. Exit 2 with a line starting `overseer:` blocks a Pre hook, or hands Claude a reminder from a Post hook.

## Known limits

- The test-runner list is a fixed regex. Add a runner when a repo needs one.
- Any failure of a test command counts as red, including "command not found".
- Red is required once per branch, not once per cycle, because refactoring on green is legitimate.
- Rule 5 cannot judge whether a cut makes sense. It sends big PRs to `split-pr-stack`, whose judgment it trusts, and does not measure PRs based on another branch. `--head` is measured when given.
- A new branch inherits the log of the closest local branch it grew from, so work carried on in a child branch does not have to see red again. Detached HEAD inherits nothing.
- Rule 7 reads line comments and docblocks, in `hooks/prose.awk`. Python docstrings are not detected, a `ponytail:` marker must fit on one line, and so must an annotation: a type split over several lines counts as prose.
- Rule 8 is a heuristic in `hooks/size.awk`, no parser per language: brace languages by brace matching (functions are blocks whose header has a parameter list; braces after `(`, `,`, `:`, `=` or `return` are literals, not blocks), Python by `def` and indentation. Ruby, multi-line strings, heredocs and template literals are not understood. The limits are fixed.

## Escape hatch

`touch .git/overseer/off` turns every rule off for the repo; `rm` it to turn them back on. It is for humans only: hotfixes and spikes. The rules forbid the agent from touching it.

## Not included, on purpose

- Human approval gates, review agents, EXPLAIN checks. Put them in a skill if you want them.
- A wall against an agent writing production files through Bash. The rules forbid it; the hooks do not police it.
- Model-judged checks. A Jev judge for rule 5 was built, benchmarked on the toucan stack and dropped in favour of `split-pr-stack`; see the design doc.

Needs `bash`, `git`, `jq`, `awk`. Design: `docs/superpowers/specs/2026-09-28-overseer-design.md`, rework: `specs/003-overseer-rework/spec.md`.

## Development

```
hooks/overseer.test.sh   # throwaway git repo, fake hook JSON in, exit codes out
```
