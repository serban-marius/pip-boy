---
name: inbox-janitor
description: "Clean the authenticated user's GitHub notification inbox and send a short digest of what still needs them. Marks as done what a rule-based snapshot proves is noise (merged/closed subjects, already-approved review requests, bot PRs, own-PR activity, CI/push/subscription chatter) and never touches mentions, assignments or pending reviews on human PRs. Use when the user says 'clean my github inbox', 'github notifications', 'inbox janitor', '/inbox-janitor', or from a scheduled OpenClaw automation."
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["gh", "jq"]}, "primaryEnv": "GH_TOKEN"}}
---

# Inbox Janitor

Keep the GitHub inbox down to what actually needs a human. Everything you post or report is in **English**. This skill only marks notification threads as done; it never approves, merges, comments, resolves or changes anything on a PR or issue.

## 1. Snapshot

Run `bin/inbox-snapshot.sh` (in this skill's directory; as a Claude Code plugin it is `${CLAUDE_PLUGIN_ROOT}/skills/inbox-janitor/bin/inbox-snapshot.sh`). It prints one JSON array with every inbox thread and a `verdict` (`done` or `keep`) plus the `rule` behind it:

| verdict | rule | meaning |
| --- | --- | --- |
| keep | `direct mention` / `direct assign` / `direct team_mention` | someone addressed the user; always kept, even on closed PRs |
| done | `pr merged` / `pr closed` | the subject is no longer open |
| done | `noise author` / `noise ci_activity` / `noise push` / `noise subscribed` | own-PR activity (covered by pr-janitor) or repository chatter |
| done | `bot pr` | review requested on a PR authored by a Bot account (dependabot, updaters) |
| done | `already approved` | review requested, and the user's latest review on it is APPROVED |
| keep | `needs you` | anything else: pending review on a human PR, comments on open items |

Trust the verdicts. Do not re-derive them by hand and do not reclassify a `keep` as `done`. If the script fails or prints nothing, stop and report the error; do not fall back to manual cleanup.

## 2. Mark done

```bash
bin/inbox-snapshot.sh > /tmp/inbox.json
jq -r '.[] | select(.verdict=="done") | .threadId' /tmp/inbox.json \
  | xargs -r -I{} gh api -X DELETE "notifications/threads/{}"
```

Marking done removes the thread from the inbox; it deletes nothing on GitHub. Count what was marked per rule for the report.

## 3. Digest

For the `keep` items, write one compact message in English, grouped as **Reviews pending** (review requests on human PRs) and **Mentions / assignments**, then anything else. One line per item: `repo#number title (author)` with the direct `https://github.com/<owner>/<repo>/pull/<n>` link. Do not read or summarize the PRs themselves; the digest is a to-do list, not a review.

Finish with one line of housekeeping: how many threads were marked done and the breakdown by rule.

If nothing is kept, say so in one line ("Inbox clean, nothing pending.") and still include the housekeeping line. A scheduled daily run always sends the digest; never return NO_REPLY from it.
