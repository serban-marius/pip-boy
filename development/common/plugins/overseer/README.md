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
| 7 | An edit adds no prose comments to code or config (annotations, tool directives and one-line `ponytail:` shortcut markers are fine); the why goes in the PR as a review comment, and after `gh pr create` the hook lists the files whose comments were stripped | after each edit, after `gh pr create` | reminder |
| 8 | A Bash write to a production file (`>`, `>>`, `&>`, `tee`, `sed -i`/`--in-place`, `perl -i`/`-pi`, including several files and trailing redirections) clears the same spec and red gates as Edit/Write | `PreToolUse` Bash | block |
| 9 | Nothing writes under `.git/overseer` or a worktree's log directory, and nothing removes or moves `.git` itself (the off switch and the logs); reads stay free | `PreToolUse` Bash | block |

## How it knows

It never learns your test command; it watches. A command that looks like a test runner (`phpunit`, `pest`, `artisan test`, `pytest`, `vitest`, `jest`, `go test`, `cargo test`, `npm test`, `deno test`…) and fails is **red**; one that succeeds is **green**. Every edit and run goes into a per-branch log at `.git/overseer/<branch>.log`, invisible to the repo.

Production code = a code file (`php js ts py go rs rb java kt swift c cs vue svelte`…) that is not a test and not under `specs/` or `openspec/`. Docs, config, JSON and YAML are always free.

Bash is classified the same way. A target taken from `>`, `>>`, `&>`, `tee [-a]`, `sed -i`/`--in-place` or `perl -i`/`-pi` goes through the production gate that Edit/Write use; several file arguments and trailing redirections such as `2>&1` or `2>/dev/null` do not hide a target. A command that writes under `.git/overseer` — or removes or moves `.git` itself — through `touch`, redirection, `&>`, `tee`, `rm`, `mkdir`, `mv`, `cp` at its destination, `ln`, `truncate`, `sed -i`, `perl -i`, `find -delete` or `dd of=` is blocked. Reads, including `cp` from the state directory, stay free; `mv` of the state directory is treated as a write on both sides. `git mv` is left alone.

Every block is logged as `<epoch> block <rule>`, and a pass of the same mode logs `<epoch> pass <mode>` and resets the streak — any pass of that mode does, even when the command is unrelated to the blocked rule. The third consecutive block of a rule logs `<epoch> escalate <rule>` and tells the agent to stop and ask the human. `bash hooks/overseer.sh stats` prints blocks per rule, escalations and the median time from a block to the next pass of the same mode, across the repo's branch and worktree logs. Each streak contributes one delta: the first block is paired with the pass that ends it, and a pass of another mode is ignored.

## Hooks

| Event | `overseer.sh` subcommand |
|-------|--------------------------|
| `SessionStart` | `session`: prints `rules/overseer.md` |
| `PreToolUse` Edit/Write/MultiEdit | `pre-edit`: rules 1, 2 |
| `PostToolUse` Edit/Write/MultiEdit | `post-edit`: logs the edit, rule 7 |
| `PreToolUse` Bash | `pre-bash`: rules 3, 5, 6, 8, 9 |
| `PostToolUse` Bash | `post-bash`: logs a green run, rules 4 and 7 (the why-comments reminder) |
| `PostToolUseFailure` Bash | `bash-failed`: logs a red run |

Exit 0 is a silent pass. Exit 2 with a line starting `overseer:` blocks a Pre hook, or hands Claude a reminder from a Post hook.

## Known limits

- The test-runner list is a fixed regex. Add a runner when a repo needs one.
- Any failure of a test command counts as red, including "command not found".
- Red is required once per branch, not once per cycle, because refactoring on green is legitimate.
- Rule 5 cannot judge whether a cut makes sense. It sends big PRs to `split-pr-stack`, whose judgment it trusts, and does not measure PRs based on another branch. `--head` is measured when given.
- A new branch inherits the log of the closest local branch it grew from, so work carried on in a child branch does not have to see red again. Detached HEAD inherits nothing.
- Rule 7 reads line comments and docblocks. Python docstrings are not detected, and a `ponytail:` marker must fit on one line (continuation lines count as prose).
- Bash write detection covers the forms above, not writes hidden inside scripts, `python -c`, `bash -c '…'`, `install`, variable indirection (`d=$(git rev-parse --git-dir); touch "$d/overseer/off"`), exotic quoting, `find` expressions that delete through a path it cannot see, or prefix commands whose own option values hide the command (`xargs -0`, `nice -n 10`, `timeout -s KILL 5`). Paths with spaces in a Bash write target are not parsed reliably. It prefers missing an unusual form to blocking a read.
- Escalation is by rule, but a pass releases the whole mode. An unrelated command that passes the same hook clears the streak; this is deliberate because the hook cannot tell which rule the next command retries.
- Inherited branch logs keep the red/green history but drop `block`, `pass` and `escalate` lines, so a child branch starts with a clean streak.

## Escape hatch

`touch .git/overseer/off` turns every rule off for the repo; `rm` it to turn them back on. It is for humans only: hotfixes and spikes. The hook blocks the agent from creating, editing or deleting anything under `.git/overseer`, and from removing or moving `.git` itself; the human does it from their own terminal.

## Not included, on purpose

- Human approval gates, review agents, EXPLAIN checks. Put them in a skill if you want them.
- Model-judged checks. A Jev judge for rule 5 was built, benchmarked on the toucan stack and dropped in favour of `split-pr-stack`; see the design doc.

Needs `bash`, `git`, `jq`. Design: `docs/superpowers/specs/2026-09-28-overseer-design.md`.

## Development

```
hooks/overseer.test.sh                    # throwaway git repo, fake hook JSON in, exit codes out
bash hooks/overseer.sh stats </dev/null  # blocks per rule, escalations, median unblock time
```
