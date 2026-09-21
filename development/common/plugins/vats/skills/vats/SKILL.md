---
name: vats
description: "V.A.T.S. (Verifiers At Tiered Stages): wire cheap, frequent verifiers into a repo as Claude Code hooks, each at its own cadence. Every edit -> lint + types on the one file; every `git commit` -> tests + contracts. A failure goes straight back to the agent, so it fixes its own mess before a human ever looks. Stack-agnostic (detects the project, uses only tools the repo already has). Also `/vats mutate <path>` for on-demand mutation testing of a sensitive module. Triggers- '/vats', 'set up verifier hooks', 'add lint/type hooks to this repo', 'make the agent check itself', 'harness this repo', '/vats mutate'. Spanish triggers also- 'monta los verificadores', 'ponle hooks de lint y tests a este repo', 'arnés para este repo', 'tests de mutación de este módulo'."
---

# vats · verifiers by cadence

Human attention costs more than tokens. Every mistake a hook catches is one the human never has to
review. So: many small, fast checks while the agent works, instead of one big review at the end.

| Cadence | What runs | Where |
|---|---|---|
| every edit | lint, types, antipatterns, **on the one file** | `PostToolUse` hook -> `vats.sh edit` -> `on_edit` |
| every `git commit` | tests, contracts | `PreToolUse(Bash)` hook -> `vats.sh commit` -> `on_commit` |
| release | integration, E2E | **CI. Not a hook.** Don't build it here. |
| now and then | mutation testing on sensitive modules | `/vats mutate <path>` (below) |

## Rules (do not break them)

- **Silent on green, short on red.** A passing check prints nothing. A failing one hands the agent the last 40 lines, not the log. Verbose hooks are context poisoning.
- **The edit cadence has a ~5 s budget.** Time every command on a real file. Anything slower, or anything that only works project-wide (`tsc`, `cargo check`, a whole-tree phpstan), moves down to the commit cadence.
- **Only tools the repo already has.** Read `composer.json`, `package.json`, `pyproject.toml`, `Makefile`, CI config. NEVER install a dependency to have something to run; list what's missing in the report instead.
- **Judge the delta, not the file.** In a legacy repo most files already break the rules (one real repo: 183 of 228 files lacked `declare(strict_types=1)`, a rule its own standards call mandatory). A whole-file check fires on every edit and pushes the agent into changes nobody asked for. Pattern rules run over `added_lines "$file"` (the lines this change adds, as `N:text`); only whole-file tools that the repo already passes clean (a formatter, a type checker) look at the full file.
- **"Couldn't run" is not "failed".** A check that can't execute (container down, tool missing) returns `$SKIP` (75) and never blocks. Otherwise a stopped dev cluster blocks every edit.
- **Pick where it lives (ask if unclear):**
  - **Personal mode (default)**: nothing lands in the repo and there is nothing to wire. This plugin's `hooks/hooks.json` already runs `hooks/vats.sh` on every edit and commit; your whole job is to write ONE file, `~/.claude/vats/<repo-name>.sh`, defining `on_edit` and `on_commit`. The script finds it by the basename of `origin`'s URL, so every worktree of the repo is covered; repos without a rules file are left alone. Use it to trial rules on a shared repo before proposing them to the team.
  - **Team mode**: `<repo>/.claude/hooks/vats.sh` + two entries in `<repo>/.claude/settings.json`, committed. Teammates get the verifiers without this plugin, through Claude Code's normal hook-trust flow. Never both modes on one repo: every check would fire twice.
- **Merge, never overwrite** `.claude/settings.json`. Show the diff.
- **Not verified = not installed.** Step 3 is not optional.

## Step 1 · find the commands

Detect the stack and pick, per cadence, the commands that already exist. Typical candidates (verify, don't assume):

| Stack | every edit (per file) | every commit |
|---|---|---|
| PHP / Laravel | `vendor/bin/pint --test F`, `vendor/bin/phpstan analyse --no-progress --error-format=raw F` (or `duster lint`) | `php artisan test --stop-on-failure` / `vendor/bin/phpunit` |
| JS / TS | `npx eslint F`, `npx prettier --check F` | `tsc --noEmit`, the `test` script (`vitest run`, `jest`) |
| Python | `ruff check F`, `ruff format --check F`, `mypy F` if fast | `pytest -x -q` |
| Go | `gofmt -l F`, `go vet ./<pkg>` | `go test ./...` |
| Rust | `cargo check` only if < 5 s, else commit | `cargo clippy -- -D warnings`, `cargo test` |

Run each candidate once on a real file and note the time. Prefer the repo's own script (`composer lint`, `npm run lint`) when it accepts a file argument.

## Step 2 · install

**Personal mode.** Write `~/.claude/vats/<repo-name>.sh` (name = `basename -s .git "$(git remote get-url origin)"`) defining `on_edit` and `on_commit`. That's all; the plugin's hooks are already live. The file is sourced by `hooks/vats.sh`, so it can use `added_lines FILE`, `$SKIP` and `$input` (the raw hook JSON). `RUNBOOK.md` at the plugin root has an annotated example.

**Team mode.**
1. Copy `../../hooks/vats.sh` (relative to this file, i.e. the plugin's `hooks/vats.sh`) to `<repo>/.claude/hooks/vats.sh`, `chmod +x`, and fill in `on_edit` and `on_commit` inside it.
2. Merge the two hook entries below into `<repo>/.claude/settings.json`. Back the file up first, merge (never overwrite), and show the diff.
3. If the user had a personal rules file for this repo, rename it so checks don't run twice.

**Either way**, when writing the checks: chain with `&&` so the first failure stops; print one short line per violation with its line number; quote the repo's own rule file when there is one (`.claude/rules/*.md`, `CLAUDE.md`), so the agent knows the rule is the team's and not yours; and make soft nudges read only the text of the current edit (`jq -r '.tool_input.new_string // .tool_input.content' <<<"$input"`) so they fire once instead of on every later edit.

Team-mode hook entries:

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/vats.sh edit", "timeout": 30 }] }
    ],
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/vats.sh commit", "timeout": 300 }] }
    ]
  }
}
```

Set the commit `timeout` (seconds) above the real duration of the test suite. If the suite takes more than ~5 minutes, put a fast subset in `on_commit` and leave the full run to CI.

## Step 3 · see it RED, then GREEN

From the repo root, with a real source file `F` (`V` = `.claude/hooks/vats.sh` in team mode, the plugin's `hooks/vats.sh` in personal mode):

```bash
echo '{"tool_input":{"file_path":"'"$PWD/F"'"}}' | CLAUDE_PROJECT_DIR=$PWD bash "$V" edit; echo "exit=$?"   # expect 0, no output
```

Then break `F` on purpose (a type error, a lint violation), run it again, and confirm **exit 2** with a short, readable message on stderr. Revert `F`. Do the same for commit:

```bash
echo '{"tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR=$PWD bash "$V" commit; echo "exit=$?"
```

If you never saw it fail, you don't know it works. Test against a throwaway copy or revert with git; never leave the deliberate violation behind. A personal rules file applies on the next edit, nothing to reload. Team-mode hooks load at session start: tell the user to open `/hooks` once or restart the session.

## Step 4 · report

What runs at each cadence with its measured time, what was pushed down to commit or left to CI and why, and what the repo is missing (no linter, no type checker, no tests) as suggestions, not actions.

## From incident to rule

When the agent makes a **new class** of mistake in this repo, don't just fix it: add the cheapest check that would have caught it to `on_edit` or `on_commit` (a grep for the banned pattern is a perfectly good verifier). Five minutes now, never again later.

## `/vats mutate <path>` · do the tests actually watch anything?

Agents write tests that touch every line and assert nothing. Coverage won't tell you; surviving mutants will. On demand, for sensitive modules only (payments, auth, customer data), it's slow:

1. Pick the tool the repo has or the stack's standard: Infection (PHP), Stryker (JS/TS/C#), mutmut (Python), PIT (Java), cargo-mutants (Rust). If it isn't installed, say so and stop; installing it is the user's call.
2. Run it **filtered to `<path>`** (e.g. `vendor/bin/infection --filter=<path> --threads=max --show-mutations`).
3. Report: mutation score, then each surviving mutant as "this change to the code broke no test", grouped by file, worst first. Propose the missing assertions; write them only if asked.

## Not included (on purpose)

- **An LLM judge on every edit** for rules a linter can't express ("`ready` is only set after init completes"). That's [lsp-smell](https://github.com/double-thinker/lsp-smell); add it when a repo has rules like that and grep can't catch them.
- **Release cadence.** Integration and E2E belong to CI.
