# vats runbook

How to set vats up, how to add a repo, how to live with it, and why each piece is the way it is.

## Why this exists

An agent writes code faster than a human can read it, so the human is the bottleneck, and human attention costs far more than tokens. Every mistake a machine catches while the agent is still working is a mistake nobody has to review, explain, or send back. You can't keep an agent aligned with something you can't verify, so vats puts cheap verifiers right where the agent works and hands it its own failures.

Six decisions follow from that. Each one is a rule you should keep when you write checks.

| Decision | Why |
|---|---|
| **Each verifier at its own cadence.** Every edit: instant, one-file checks. Every commit: tests. Release: CI, not here. | Feedback is worth more the sooner it arrives, but only if it's cheap. A 40-second check on every edit stalls the agent; a lint error found at release costs a whole round trip. |
| **Judge only the lines the change adds.** Rules read `added_lines "$file"`, not the file. | Legacy code breaks today's rules everywhere (in the first repo this ran on, 183 of 228 files lacked a "mandatory" `declare(strict_types=1)`). A whole-file check fires on every edit and pushes the agent into changes nobody asked for. New code must comply; old code is left alone. |
| **Silent on green, short on red.** No output on success; at most the last 40 lines on failure. | Hook output lands in the agent's context. Noise there is context poisoning: the agent starts acting on it. |
| **"Couldn't run" is not "failed".** A check that can't execute returns `$SKIP` and never blocks. | Otherwise a stopped dev cluster or a missing tool blocks every edit, and the first thing anyone does is turn vats off. |
| **Rules come from the team's written standards and say so.** Each message cites its source (`comments.md`, `CLAUDE.md`…). | The agent weighs "the repo's rule" differently from "some hook's opinion", and a teammate reading the rules file can check each line against the doc. It also keeps you honest: if it isn't written down, it's your taste, not a rule. |
| **From incident to rule.** When the agent makes a new class of mistake, add the cheapest check that would have caught it. | Five minutes once, instead of the same review comment forever. A `grep` is a perfectly good verifier. |

What vats deliberately does **not** do: judge meaning. "This comment explains *what*, not *why*" can't be grepped. The most vats does is nudge once and let the agent decide. If a repo collects several rules like that, the next step is an LLM judge at the commit cadence (a `prompt`-type hook, or [lsp-smell](https://github.com/double-thinker/lsp-smell)), not more regexes.

## Two modes

- **Personal (default).** The plugin ships the hooks. You write one small rules file per repo in `~/.claude/vats/`. Nothing lands in the repo, so you can trial rules on a shared codebase without asking anyone. The rules file is found by the name of the repo's `origin`, so every worktree of that repo is covered.
- **Team.** A copy of the script and two hook entries are committed to the repo, so every teammate gets the verifiers without installing anything, through Claude Code's normal hook-trust prompt. Graduate a repo to team mode once the rules have proven themselves in personal mode.

Don't run both on the same repo: every check would fire twice.

## 1. Install (once per machine)

Requires `bash`, `git` and `jq`.

```
/plugin marketplace add git@github.com:serban-marius/pip-boy.git     # or a local checkout: /plugin marketplace add ~/Developer/pip-boy
/plugin install vats@pip-boy
```

Then check it took: `/hooks` should list, under the plugin, `PostToolUse · Edit|Write` and `PreToolUse · Bash`, both running `hooks/vats.sh`.

At this point vats does nothing anywhere: no repo has a rules file yet. That is the intended resting state. The hooks cost a few hundredths of a second per call and print nothing.

**Coming from the hand-wired setup** (two `vats.sh` entries in `~/.claude/settings.json` and a `~/.claude/vats/vats.sh`): once the plugin is installed, delete those two entries (via `/hooks`, or by hand) and delete `~/.claude/vats/vats.sh`. Keep the `<repo-name>.sh` rules files; they are read from the same place.

## 2. Add a repo (personal mode)

Easiest: open a session in the repo and run `/vats`. The skill reads the repo's standards and tooling, proposes the rules, writes the file and proves it. By hand:

**a. Name the file after the repo.** `git remote get-url origin` ends in `…/catalog-api.git` → `~/.claude/vats/catalog-api.sh`.

**b. Find the rules before you write any.** Read the repo's own standards (`.claude/rules/`, `CLAUDE.md`, `CONTRIBUTING`, linter configs). Then measure, don't guess: run each candidate pattern over the current code and over the git history. If a rule would fire on most of the legacy code, it must be delta-only. If it fires on nothing the agent has ever written, it's not worth having.

**c. Write the two functions.** The file is sourced by the script, so it has these available: `added_lines FILE` (prints `N:text` for each added line; a file git doesn't know yet counts whole), `$SKIP`, and `$input` (the raw hook JSON).

```bash
# ~/.claude/vats/my-repo.sh
on_edit() {                       # $1 = absolute path of the edited file
  case "$1" in */vendor/*) return 0 ;; *.php) ;; *) return 0 ;; esac
  local added bad=0
  added=$(added_lines "$1")

  if hits=$(grep -E '^[0-9]+:(.*[^A-Za-z_>:$])?(dd|dump|var_dump)\(' <<<"$added"); then
    printf -- '- Debug leftover. Remove it.\n%s\n' "$(sed 's/^/    line /' <<<"$hits")"; bad=1
  fi
  return $bad                     # 0 = pass, non-zero = the text above goes to the agent
}

on_commit() {                     # runs before every `git commit` the agent issues
  command -v vendor/bin/phpunit >/dev/null || return "$SKIP"
  vendor/bin/phpunit --stop-on-failure
}
```

Writing good checks:

- **Edit cadence budget: about 5 seconds.** Time every command on a real file. Anything slower, or anything that only works project-wide (`tsc`, `cargo check`, a whole-tree static analysis), belongs in `on_commit`.
- **One short line per violation, with the line number and the source of the rule.** That is all the agent needs to fix it.
- **A nudge fires once.** For soft rules ("you added a comment, keep it only if it says why"), check the text of *this* edit (`jq -r '.tool_input.new_string // .tool_input.content' <<<"$input"`) rather than the whole delta, or it repeats on every later edit of the file until commit.
- **Tools that run in a container** must return `$SKIP` when the container isn't there, not their own error code.
- **Only tools the repo already has.** Never install a dependency to have something to run.

**d. See it red, then green.** From the repo root, with a real file `F`:

```bash
V=$(find ~/.claude/plugins/cache -path '*vats*/hooks/vats.sh' | tail -1)
echo '{"tool_input":{"file_path":"'"$PWD/F"'"}}' | CLAUDE_PROJECT_DIR=$PWD bash "$V" edit; echo "exit=$?"
```

Expect `exit=0` and no output. Now add a violation to `F`, run it again, and expect `exit=2` with your message. Revert `F`. Same for commits: `echo '{"tool_input":{"command":"git commit -m x"}}' | … commit`. If you never saw it fail, you don't know it works. Changes to a rules file apply immediately; there is nothing to reload.

## 3. Living with it

- **What the agent sees.** After an edit, a failing check reaches it as a reminder (the edit itself already happened) and it fixes the file on its next step. Before a commit, a failing check blocks the commit and the agent gets the tail of the test output.
- **What you see.** Nothing, when it works. Claude Code only surfaces a hook that errors or is slow. To watch hooks run, start with `claude --debug`.
- **A rule misfires.** Fix the pattern in the rules file; it applies on the next edit. If you can't make it precise, delete it: a verifier that cries wolf makes the agent "fix" correct code, which is worse than no verifier.
- **Turn it off.** One repo: rename its rules file. Everything: disable the plugin in `/plugin`.
- **Mutation testing.** `/vats mutate <path>` on a sensitive module answers a different question: do the tests the agent wrote actually assert anything? Run it now and then, not on a cadence.

## 4. Graduating a repo to team mode

When the rules have run for a while without false alarms and you want the whole team to have them: run `/vats` in the repo and choose team mode. It copies `hooks/vats.sh` to `<repo>/.claude/hooks/vats.sh`, moves your two functions into it, and merges two entries into `<repo>/.claude/settings.json`:

```json
{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/vats.sh edit",   "timeout": 30  }] }
{ "matcher": "Bash",       "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/vats.sh commit", "timeout": 300 }] }
```

Commit both, open a PR like any other change, and rename your personal rules file for that repo so the checks don't run twice. If the organisation generates its repos from a base template, the template is the right home: propose it there.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Nothing ever fires in a repo | No rules file, or its name doesn't match: compare `basename -s .git "$(git remote get-url origin)"` with the file name. No `origin` remote → no match. |
| Nothing fires anywhere | Plugin disabled, or the session predates the install: open `/hooks` once or restart the session. |
| Every check fires twice | Personal and team mode on the same repo, or leftover hand-wired entries in `~/.claude/settings.json`. Remove one. |
| Edits or commits are blocked when the dev environment is down | A check returns its own error code instead of `$SKIP` when it can't run. |
| `vats: jq not found, verifiers are OFF` | Install `jq`. vats reports this as a non-blocking error rather than failing silently. |
| The agent keeps being told about the same soft rule | The nudge is reading the whole delta. Make it read this edit only (see 2c). |
| Commit check times out | The suite is slower than the hook's 300 s timeout. Put a fast subset in `on_commit` and leave the full run to CI. |
| A commit by the agent skipped the tests | The command wasn't recognisably a `git commit` in one segment (the match is deliberately loose, not a shell parser). CI is the backstop. |

Self-check of the script itself: `hooks/vats.test.sh` (fake hook JSON in, exit codes out).
