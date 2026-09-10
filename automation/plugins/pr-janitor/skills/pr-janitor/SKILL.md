---
name: pr-janitor
description: "Keep the authenticated GitHub user's open, ready-for-review pull requests healthy: fix failing CI, address still-valid review feedback, drive checks green on the latest head, and report with direct PR links. Never posts redundant comments and never resolves threads a human took part in. Use when the user says 'pr janitor', 'fix my PRs', 'address the review comments', 'keep my PRs green', '/pr-janitor', or from a scheduled OpenClaw automation."
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["git", "gh", "jq"]}, "primaryEnv": "GH_TOKEN"}}
---

# PR Janitor

Maintain pull requests without creating review noise. Use `gh` and `git`. Everything that touches GitHub or reaches the user (commits, replies, PR text, run reports) is written in **English**.

The one rule that matters: **never act on a finding you have not proven is still open on the current head.** Reviewers, CI and other agents move faster than you. A comment that was true an hour ago is often already fixed.

## Snapshot tool

`bin/pr-snapshot.sh <owner/repo> <number>` (in this skill's directory; as a Claude Code plugin it is `${CLAUDE_PLUGIN_ROOT}/skills/pr-janitor/bin/pr-snapshot.sh`) prints one JSON document with:

- `pr`: state, `isDraft`, author, `headRefOid`, branches, `reviewDecision`.
- `checks`: rollup state and every check attached to **that** head SHA.
- `reviewThreads[]`: `isResolved`, `isOutdated`, `path`, `rootAuthor.type`, and every comment with `author.type` (`User`, `Bot`, `Mannequin`...), `outdated`, `commit`, `replyTo`.
- `reviews[]` and `issueComments[]`.

Always use it instead of assembling the state by hand. Re-run it before every mutation; a snapshot is stale the moment you push or someone else does.

## 1. Scope

1. `gh auth status` must succeed. `LOGIN=$(gh api user --jq .login)`.
2. Candidates: the PR(s) the user named, or for an unattended run
   `gh search prs --author "$LOGIN" --state open --json number,url,repository,isDraft,title`.
3. Keep only PRs that are open, not draft, and authored by `$LOGIN`. Apply any repo or PR filter from the request. Organization repos are in scope.
4. Hard limits in every repo, personal or organization: never merge, close, reopen, relabel, edit the PR title/body, request reviewers, or force-push. Never touch a PR outside the list from step 3.

## 2. Snapshot

For each candidate, run the snapshot tool and clone or fetch the repo into `~/repos/<repo>` (create it if needed). Check out `headRefName` and confirm `git rev-parse HEAD` equals `pr.headRefOid`. If the PR is no longer open, non-draft and yours, drop it.

## 3. Prove work remains

Build the work queue from the snapshot only. An item is actionable only if you can point at current evidence on `headRefOid`:

- **Failing check**: `checks.contexts[]` with `conclusion` in `FAILURE`, `TIMED_OUT`, `CANCELLED`, `ACTION_REQUIRED` or `ERROR`. Read the failed job log (`gh run view <id> --log-failed`) and reproduce locally when practical.
- **Review finding**: the thread is `isResolved: false`, the complaint is still visible in the current code at `path`, and no later comment in the thread (from anyone) or later commit already addresses it. `isOutdated: true` or a comment `commit` older than the head is a strong hint the finding is already handled; verify against the code before deciding.

Everything else is **no-action**: fixed, outdated, resolved, duplicated, superseded, non-reproducible, praise, status messages, optional suggestions, `SKIPPED`/`NEUTRAL` checks. For no-action items make no change, post nothing, resolve nothing. Do not post "already fixed", "acknowledged" or "thanks". Mention skips only in the private run report.

If the queue is empty, go to step 7.

## 4. Fix

Work on the PR branch. Make the smallest change that resolves the actionable item. Run the focused tests, then the project's usual checks (lint, static analysis, test suite) as far as they run locally. Commit with a conventional English message and `git push` (never `--force`).

After every push: re-run the snapshot, confirm `headRefOid` is your commit, and re-classify the remaining queue against it.

## 5. Reply and resolve

Immediately before any reply or thread resolution, re-run the snapshot. If the head, the thread or its comments changed since you decided, decide again.

Account type comes from `author.type` in the snapshot, never from the login. Unknown counts as `User`.

- A thread is **human** if any comment in it, root or reply, is from a `User` other than `$LOGIN`. Reply only when this run pushed a change that addresses it, in one concise English comment citing the commit and file. **Never resolve a human thread.**
- A thread is **bot** if every comment is from `Bot` accounts (plus your own earlier replies). After the fix is on the current head and verified, reply only if it adds evidence not already in the thread, then resolve it with the `resolveReviewThread` GraphQL mutation. Re-check that it is still unresolved right before the mutation.
- Before posting anything, scan the thread and the PR comments for an equivalent existing reply. Never post a duplicate.

## 6. CI on the latest head

Read checks only from a snapshot whose `headRefOid` equals the remote head. Wait for pending required checks when the run is expected to leave the PR green. Never report green based on an earlier SHA. A blocker is only something you cannot fix from here: missing credentials, external infrastructure, a product decision.

## 7. Report

In English, compact, one bullet per PR, always with the direct `https://github.com/<owner>/<repo>/pull/<n>` link. Per PR: head SHA and CI state, what changed and how it was verified, human threads replied (still open), bot threads resolved, skipped items with the reason, blockers.

Unattended runs (OpenClaw automation): if no PR changed and there is no new blocker, return exactly `NO_REPLY`.
