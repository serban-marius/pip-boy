# reachable-workers: mister-handy workers HQ can reach, see and trust (1.4.0)

## Why
One HQ session ran four Orca workers on a UI feature for an evening. The briefs and STATUS protocol
held up; the plumbing around them did not:
- `orca worktree create --agent claude` followed the user's Chat UI setting, so workers started as
  chat sessions with no terminal handle: HQ could not send them a follow-up, approval or hand-off.
- Workers sat on permission prompts for 25–45 minutes. Their Orca cards said `blocked`, but nothing
  reached `STATUS.md`, and `QUIET` only fires after 20 minutes of silence.
- HQ stacked work on a feature branch that was already in the integration branch under other shas.
- The user saw nothing of a UI task for hours; the one preview showed the old UI because the
  worker had reverted its tree to take "before" screenshots.
- FYI hand-offs between workers woke HQ for nothing.

## What we already know
- Plugin: `development/common/plugins/mister-handy/` (1.3.0), skill `skills/delegate/`:
  `SKILL.md`, `bin/watch.sh <hq dir> [quiet minutes]` (blocks on `_hq/STATUS.md`, prints what HQ
  must act on, exits; remembers its offset in `<hq>/.watch-offset`), `bin/closable.sh`, and
  `bin/delegate.test.sh` (bash, `gh` stubbed). Read watch.sh and the test first.
- Worker worktrees are siblings of the `_hq/` dir: the slug of a worker is its worktree path
  relative to `dirname <hq dir>`.
- `orca worktree ps --limit 1000 --json` prints
  `{"result":{"worktrees":[{"path":"<abs path>","status":"<e.g. permission|working|idle>","agents":[{"state":"<blocked|waiting|working|...>","stateStartedAt":<epoch ms>,"lastAssistantMessage":"<text>"}]}]}}`.
  A card is on a permission prompt when its `status` is `permission` or any agent's `state` is
  `blocked`.

## Task
1. `specs/005-mister-handy-reachable-workers/spec.md` (Why / What changes / How we'll know).
2. `watch.sh`:
   - `HANDOFF-FYI` lines (a worker telling another something HQ need not act on) stay in STATUS
     and do **not** wake the watcher; `HANDOFF` still does.
   - Every minute (first tick immediately) poll `orca worktree ps --limit 1000 --json`. For a card
     whose slug is live (dispatched by HQ and not settled) and that has been on a permission prompt
     for 60 s or more (now − the blocked agent's `stateStartedAt`), print
     `WAITING-APPROVAL <slug> <lastAssistantMessage>` with every run of whitespace (spaces,
     newlines) collapsed to one space, cut to 200 characters, and exit.
   - Once per prompt: the same slug with the same `stateStartedAt` never wakes HQ twice, across
     watcher runs (remember it in a file under the hq dir); a new `stateStartedAt` wakes it again.
     A prompt younger than a minute prints nothing yet. Cards of slugs HQ did not dispatch are
     ignored. Without `orca` or `jq` on PATH, skip the check silently.
   - Update the header comment listing exit lines.
3. `SKILL.md` (README in step): launch a worker with `orca worktree create`, then
   `orca terminal create --command 'claude --permission-mode auto'`, `wait tui-idle` and
   `terminal send` of the launch prompt; the launch only counts with a `term_...` handle, a satisfied
   wait and an accepted send (otherwise tell the user, record nothing). Event table row for
   `WAITING-APPROVAL` (tell the user at once). A base-branch check before stacking work (integration
   branch from recent merged PR bases, `git cherry` / ahead-behind for other candidates); the brief
   names the base and PR target. UI tasks: the brief asks for `ANSWER PREVIEW <url> <login>` within
   ~20 min and `ANSWER PUNCH-LIST <path>` before a design change; "before" screenshots come from the
   base in another checkout, never by reverting the working tree. Workers read STATUS lines for
   their slug before each MILESTONE/DONE; `HANDOFF-FYI` for hand-offs that need no forwarding.
   `hq NOTE <slug> ...` when HQ cannot reach a worker. Fan-out by what the user will see first.
4. Bump mister-handy to 1.4.0 in its `plugin.json` and `.claude-plugin/marketplace.json`.

## Acceptance
- `delegate.test.sh` gets an `orca` stub on PATH (prints a JSON file you control) and cases for:
  HANDOFF-FYI does not wake; a dispatched worker on a prompt for over a minute prints
  `WAITING-APPROVAL <slug> <message>` (whitespace collapsed); under a minute it does not; the same
  prompt wakes once, a new `stateStartedAt` wakes again; a card for a slug HQ did not dispatch is
  ignored. The whole file is green, existing cases included.
- Commit message in the repo's style, e.g. `feat(mister-handy): ... (1.4.0)`.
