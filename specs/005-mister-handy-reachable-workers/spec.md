# 005 · mister-handy workers HQ can reach, see and trust

## Why

One HQ session ran four Orca workers on a UI feature for an evening (teros terminal-gem,
2026-10-20). The briefs and STATUS protocol held up; the plumbing around them did not:

- `orca worktree create --agent claude` follows the user's Chat UI setting, so the workers
  started as chat sessions: no terminal handle, `orca terminal list` empty. HQ could not send
  them a follow-up, an approval, a hand-off or a new spec.
- Workers sat on permission prompts for 25–45 minutes. Their Orca cards said `blocked`, but
  nothing reached `STATUS.md`, and `QUIET` only fires after 20 minutes of silence.
- HQ stacked the work on a feature branch that was already in the integration branch (`dev`,
  not `main`) under other shas; every PR had to be rebased and retargeted.
- The user saw nothing of a UI task for hours, and when a preview existed it showed the old UI:
  the worker had reverted its working tree to take "before" screenshots.
- Hand-offs between workers waited for HQ to forward them, and FYI hand-offs woke HQ for nothing.
- The work was split by files (backend, window, login) instead of by what the user would look at.

## What changes

| Case | Today | After |
|---|---|---|
| Launching a worker | `worktree create --agent claude --prompt ...`; chat or terminal per Chat UI setting | `worktree create`, then `terminal create --command 'claude --permission-mode auto'`, `wait tui-idle`, `terminal send`; the launch counts only with a `term_...` handle, a satisfied wait and an accepted send, otherwise HQ tells the user and records nothing |
| Permission prompts | invisible until `QUIET` | workers start in `auto` permission mode; the watcher polls `orca worktree ps` every minute and prints `WAITING-APPROVAL <slug> <last message>` for a dispatched worker on a prompt for a minute or more, once per prompt; HQ tells the user at once |
| Base branch | repo default, or the current branch when stacked | a base check first: the integration branch from recent merged PR bases, `git cherry` and ahead/behind for any other candidate; the brief names the base and the PR target |
| UI tasks | nothing visible until DONE | the brief asks for `ANSWER PREVIEW <url> <login>` within ~20 min and `ANSWER PUNCH-LIST <path>` with screenshots before a design change; HQ relays both at once |
| "Before" screenshots | whatever the worker does | from the base in another checkout or the deployed app, never by reverting the working tree |
| Hand-offs | HQ forwards every `HANDOFF` | workers also read STATUS lines for their slug before each MILESTONE/DONE; `HANDOFF-FYI` stays in STATUS and does not wake HQ |
| A worker HQ cannot reach | silent | `hq NOTE <slug> ...` in STATUS, and the user is told |
| Fan-out | one owner per file | first by what the user will see: that slice goes first with the first preview |

## How we'll know it works

`skills/delegate/bin/delegate.test.sh`, with `gh` and `orca` stubbed:

- `HANDOFF-FYI` does not wake the watcher;
- a dispatched worker whose card is on a permission prompt for over a minute prints
  `WAITING-APPROVAL <slug> <message>` (whitespace collapsed); under a minute it does not;
- the same prompt wakes HQ once, a new prompt (new `stateStartedAt`) wakes it again;
- a card on a prompt for a slug HQ did not dispatch is ignored.

Run against the live teros cards, the watcher printed `WAITING-APPROVAL tg-window-ux ...` on its
first tick.
