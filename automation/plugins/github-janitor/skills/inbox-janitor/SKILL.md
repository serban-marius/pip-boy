---
name: inbox-janitor
description: "Clean the authenticated user's GitHub notification inbox and send a short digest of what still needs them. Marks as done what a rule-based snapshot proves is noise (merged/closed subjects, already-approved review requests, bot PRs, own-PR activity, CI/push/subscription chatter) and never touches mentions, assignments or pending reviews on human PRs. Use when the user says 'clean my github inbox', 'github notifications', 'inbox janitor', '/inbox-janitor', or from a scheduled OpenClaw automation."
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["gh", "jq"]}, "primaryEnv": "GH_TOKEN"}}
---

# Inbox Janitor

Keep the GitHub inbox down to what actually needs a human. Everything you post or report is in **English**. This skill only marks notification threads as done; it never approves, merges, comments, resolves or changes anything on a PR or issue.

## 1. Clean

Run `bin/inbox-clean.sh` (in this skill's directory; as a Claude Code plugin it is `${CLAUDE_PLUGIN_ROOT}/skills/inbox-janitor/bin/inbox-clean.sh`). It snapshots every inbox thread, marks as done the ones a rule proves are noise, remembers them in a state file (the notifications API keeps listing done threads; only the UI hides them), and prints one JSON summary:

```json
{ "dryRun": false, "markedTotal": 103, "marked": {"pr merged": 47, "already approved": 31}, "failed": 0,
  "kept": [ {"reason": "review_requested", "rule": "needs you", "repo": "org/repo", "number": "153", "title": "...", "author": "login", "url": "https://github.com/org/repo/pull/153"} ] }
```

Rules behind the verdicts (`bin/inbox-snapshot.sh` if you want the raw list):

| verdict | rule | meaning |
| --- | --- | --- |
| keep | `direct mention` / `direct assign` / `direct team_mention` | someone addressed the user; always kept, even on closed PRs |
| done | `pr merged` / `pr closed` | the subject is no longer open |
| done | `noise author` / `noise ci_activity` / `noise push` / `noise subscribed` | own-PR activity (covered by pr-janitor) or repository chatter |
| done | `bot pr` | review requested on a PR authored by a Bot account (dependabot, updaters) |
| done | `already approved` | review requested, and the user's latest review on it is APPROVED |
| keep | `needs you` | anything else: pending review on a human PR, comments on open items |

Trust the summary. Do not mark anything done by hand, do not reclassify a `keep`, and never call the notifications API yourself. If the script fails or prints no JSON, stop and report the error verbatim. `--dry-run` shows what would be marked without touching anything.

## 2. Digest

For the `kept` items, write one compact message in English, grouped as **Reviews pending** (review requests on human PRs) and **Mentions / assignments**, then anything else. One line per item: `repo#number title (author)` with the direct `https://github.com/<owner>/<repo>/pull/<n>` link. Do not read or summarize the PRs themselves; the digest is a to-do list, not a review.

Finish with one line of housekeeping from `markedTotal` and `marked` (and `failed` if non-zero).

If nothing is kept, say so in one line ("Inbox clean, nothing pending.") and still include the housekeeping line. A scheduled daily run always sends the digest; never return NO_REPLY from it.
