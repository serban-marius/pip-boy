---
name: pr-janitor
description: "Maintain the user's open pull requests when asked to fix CI, address review feedback, or watch authored PRs. Refreshes the latest GitHub state before every action, skips findings already handled, never resolves human threads, and reports direct PR links."
---

# PR Janitor

Keep eligible pull requests healthy without generating redundant GitHub activity. Use `gh` for GitHub operations and `git` for local branches and commits.

Write all GitHub-facing content in English, including commits, replies, PR text, automation notifications, and status reports.

## 1. Establish authorized scope

Run `gh auth status`, then resolve the authenticated login with `gh api user --jq .login`.

For a specific PR, confirm that it is open, not a draft, and authored by that login unless the user explicitly authorizes a broader scope. For a watch run, discover open PRs authored by that login and exclude drafts. Apply repository, organization, or PR filters from the request.

Never mutate a PR outside the authorized scope. Never merge, close, relabel, or force-push. Finish this step only with an explicit list of eligible PRs.

## 2. Build a latest-head snapshot

Before editing code or posting anything, collect the PR state, author, draft status, head SHA, head branch, base branch, commits, files, reviews, comments, and checks:

```bash
gh pr view <number> --repo <owner/repo> \
  --json number,url,state,isDraft,author,headRefOid,headRefName,baseRefName,reviewDecision,statusCheckRollup,comments,reviews,commits,files
gh api "repos/<owner/repo>/pulls/<number>/comments"
gh api "repos/<owner/repo>/issues/<number>/comments"
gh pr diff <number> --repo <owner/repo>
git fetch origin <head-branch>
```

Query `repository.pullRequest.reviewThreads` with `gh api graphql`. Follow pagination and collect each thread's ID, resolution state, path, current/original line, and chronological comments. For every comment, collect its ID, body, timestamps, outdated state, commit OID, reply relationship, and author login plus GraphQL `__typename`.

Confirm that the PR is still eligible and the checked-out commit equals `headRefOid`. Include later replies, newer commits, resolved/outdated state, current code, current diff, and checks attached to that exact SHA. Finish only with one internally consistent snapshot.

## 3. Prove that work remains

Reproduce each failing check where practical. Inspect every review finding against the current code and latest conversation.

Classify a finding as actionable only when current evidence proves it remains unresolved on the snapshot SHA. Classify it as no-action when it is fixed, stale, outdated, duplicated, resolved, non-reproducible, or superseded by a later commit or reply.

For no-action findings:

- make no code change;
- post no acknowledgement, status, or "already fixed" reply;
- do not reopen or resolve any thread;
- mention the skip only in the private run report when useful.

Ignore praise, status-only messages, and suggestions that do not require a change. Finish this step with an evidence-backed queue containing only current actionable work.

## 4. Make minimal verified fixes

Check out the PR head branch without overwriting unrelated local changes. Apply only the changes required by the actionable queue. Run focused tests first, then the relevant project checks.

Commit and push normally with an English message. After every push, discard the previous snapshot and repeat Steps 2 and 3 against the new `headRefOid`. Finish only when the latest remote head contains the verified fix or a concrete blocker prevents progress.

## 5. Reply without review noise

Immediately before any GitHub reply or thread-resolution mutation, refresh the complete snapshot. If the head SHA, code, diff, thread state, or comments changed, reclassify the finding before acting. Search the thread and PR comments for an equivalent later reply; never post a duplicate.

Determine the root review author's account type from GraphQL `__typename` or GitHub's explicit account `type`. Treat an unknown type as human; never infer bot status from the username alone.

- For a human-authored root comment, reply only when this run made a new material change that addresses a still-open finding. Cite concise evidence such as the commit, file, test, or check. Never resolve the thread.
- For a bot-authored root comment, reply only when fresh evidence adds value and no equivalent reply exists. Resolve the thread only after the fix is verified on the current head and a final freshness check still shows it open and actionable.

Every reply must be concise, factual, and in English. Finish this step with all human threads left unresolved and every bot-thread mutation tied to the same current snapshot.

## 6. Drive current CI green

Read checks only from a refreshed snapshot whose `headRefOid` matches the remote head. Investigate failed required checks, reproduce them where possible, apply the smallest verified fix, push, and restart from Step 2.

Wait for pending required checks when the run is expected to finish the PR. Report a blocker only when it requires unavailable credentials, external infrastructure, new authorization, or a product decision. Never claim green from an earlier SHA.

## 7. Report with direct links

Report in English. Include a direct clickable `https://github.com/<owner>/<repo>/pull/<number>` URL for every PR mentioned.

Summarize:

- latest head SHA and CI state;
- material code changes and verification;
- human replies posted, with human threads still open;
- bot threads resolved;
- stale or already-handled findings skipped without GitHub activity;
- concrete blockers.

Keep scheduled-run notifications compact. Stay silent when nothing changed and there is no new blocker.
