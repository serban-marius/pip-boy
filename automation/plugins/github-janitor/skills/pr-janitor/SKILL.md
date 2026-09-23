---
name: pr-janitor
description: "Keep the authenticated GitHub user's open, ready-for-review pull requests healthy: address still-valid review feedback, report failing CI for manual analysis, and drive checks green with direct PR links. Never posts redundant comments and never resolves threads a human took part in. Use when the user says 'pr janitor', 'fix my PRs', 'address the review comments', 'keep my PRs green', '/pr-janitor', or from a scheduled OpenClaw automation."
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["git", "gh", "jq"]}, "primaryEnv": "GH_TOKEN"}}
---

# PR Janitor

Decide **which** pull requests deserve work and **whether to say anything at all**. The work on a single PR — verifying findings, replying, resolving — belongs to the `pr-address-comments` skill, in `../pr-address-comments/SKILL.md` next to this file. Read it once you have picked a PR and follow it, with the silence rule below layered on top.

The one rule that matters here: **never act on a finding you have not proven is still open on the current head.** Reviewers, CI and other agents move faster than you. A comment that was true an hour ago is often already fixed, and answering it again is worse than saying nothing.

**Unattended runs (scheduled automations):** first run `test -x /usr/bin/gh.real`. If it fails, the host guardrail shims from `../../guardrails/install.sh` are not installed: do nothing on GitHub and report "guardrails missing on this host" as the only blocker.

## Tools

Both live in this skill's directory (`${CLAUDE_PLUGIN_ROOT}/skills/pr-janitor/bin/` as a Claude Code plugin):

- `bin/pr-fingerprint.sh` — one line per eligible PR: head SHA, `updatedAt`, check rollup, unresolved thread count. One GraphQL call. This is what the scheduled trigger compares between runs.
- `bin/pr-snapshot.sh <owner/repo> <number>` — the full current state of one PR: checks on that exact SHA, review threads with `isResolved`, `isOutdated` and each author's account type, reviews and issue comments.

Use them instead of assembling state by hand, and re-run the snapshot before every mutation: it is stale the moment you push or someone else does.

## 1. Scope

1. `gh auth status` must succeed. `LOGIN=$(gh api user --jq .login)`.
2. **If the run message names the PRs that changed, those are your entire scope.** The scheduled trigger has already compared fingerprints and tells you exactly which ones moved. Do not sweep the others: they are unchanged since a previous run that already cleared them, and re-reading them is the single most expensive thing this job can do.
3. Only when no PR is named — a manual run, or a first run with no previous state — discover candidates with `gh search prs --author "$LOGIN" --state open --json number,url,repository,isDraft,title`.
4. Keep only PRs that are open, not draft, and authored by `$LOGIN`. Organization repos are in scope.
5. Hard limits everywhere: never merge, close, reopen, relabel, edit the PR title or body, request reviewers, or force-push. The host shims refuse these anyway. Never touch a PR outside the list above.

## 2. Triage before you descend

For each PR in scope, run `bin/pr-snapshot.sh` and decide whether there is anything worth a deep pass:

- a review thread has `isResolved: false` and its last comment is not already an answer from you.

**Failing CI checks are reported but not automatically fixed** — they go in the report with check name and detailsUrl for manual analysis.

A PR with green checks and nothing unresolved is done. Record it and move on — do not read its diff, do not clone it.

`isOutdated: true`, or a comment pinned to a SHA older than the head, means the code moved under the finding. That is a strong hint it is already handled, but it is a hint: check the current code before deciding either way.

## 3. Deep pass: follow pr-address-comments

For each PR that survived triage, read `../pr-address-comments/SKILL.md` and do what it says: read files at the PR's SHA, separate each finding's premise from its conclusion, reach a verdict of correct / false positive / out of scope, fix what is genuinely broken, commit, push, reply with reproducible evidence, and resolve bot threads only.

Two additions for unattended work:

- **Silence is the default.** That skill replies to every unresolved thread it looked at; here you reply only when this run produced something new to say — a fix you just pushed, or evidence refuting a finding nobody has refuted yet. Before posting, scan the thread and the PR comments for an equivalent reply and never write a second one. Post no acknowledgements, no "already fixed", no status updates.
- **Bot feedback is welcome on false positives.** When you refute a bot finding with evidence, include the "Feedback for the bot" block from that skill's template. It is what makes the reviewer better, and it only ever appears in a reply you were already going to post.

After every push, re-run the snapshot, confirm the head is your commit, and re-triage what is left against it.

## 4. Report

In English, compact, one bullet per PR, always with the direct `https://github.com/<owner>/<repo>/pull/<n>` link. Per PR: head SHA and CI state, what changed and how it was verified, human threads replied to (still open), bot threads resolved, findings skipped with the reason, blockers.

**Failing CI checks:** list each one with its name and `detailsUrl` so you can investigate manually. Format:
- `❌ [Check Name](detailsUrl) — check logs for details`

Example: `❌ [Run CI tests](https://github.com/softonic-development/apk-signature-provider/actions/runs/35227351827/job/106703547019) — check logs for details`

A blocker is only something you cannot fix from here: missing credentials, external infrastructure, a product decision. Never report green from an earlier SHA.

Unattended runs: silence applies to the report too. Return exactly `NO_REPLY` unless this run changed code, posted a reply, resolved a thread, hit a blocker, **or found failing CI checks**. A PR you triaged as clean is not news, however it entered your scope: a run that swept ten PRs and found nothing to do still returns `NO_REPLY`.
