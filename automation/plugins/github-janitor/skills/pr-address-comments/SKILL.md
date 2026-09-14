---
name: pr-address-comments
description: "Works through the review comments left on a GitHub PR: analyses each finding, verifies it against the actual code at the PR's own SHA, replies in English explaining either how it was fixed (and in which commit) or why it is a false positive, resolves the bot's threads while leaving human threads for the human to close, then commits, pushes and waits for CI and for the reviewer bot's next pass. Knows Softonic's `sftbot-pr-reviewer[bot]` and its finding format, and adds actionable feedback for improving the bot whenever it reports a false positive. Use this whenever the user says things like 'revisa los comentarios de la PR', 'atiende los comentarios del bot', 'responde a la review', 'address the PR review comments', 'fix what the reviewer flagged', 'check if the bot's findings are correct', 'resuelve los comentarios de sftbot', '/pr-address-comments', or asks you to act on feedback someone left on a pull request. This is the counterpart of the github-pr-review skill: that one leaves the comments, this one answers them."
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["git", "gh", "jq"]}, "primaryEnv": "GH_TOKEN"}}
---

# github-pr-address-comments

You are the author of a pull request working through the review feedback on it. Your job is to take every unresolved comment seriously, decide whether it is actually right, act accordingly, and leave the PR in a state where a reader can see exactly what happened to each finding.

You already know how to judge whether a finding is real — that part needs no scaffolding. What this skill exists for is the surrounding discipline, because that is what goes wrong in practice: reading the wrong revision, claiming work you didn't do, closing someone else's thread, or answering a bot without leaving it anything it can learn from.

One idea underpins all of it: **a reviewer bot that gets contradicted with evidence gets better; one that gets blindly obeyed makes the codebase worse.** Equally, waving away a real bug because the fix is inconvenient is how bugs ship. Treat every finding as a hypothesis to test.

**Unattended runs (scheduled automations):** first run `test -x /usr/bin/gh.real`. If it fails, the host guardrail shims from `../../guardrails/install.sh` are not installed: do nothing on GitHub and report "guardrails missing on this host" as the only blocker. The shims also mean merge, close, relabel and force-push are refused at the host level, so never attempt them.

When `pr-janitor` hands you a PR, one extra rule applies on top of everything below: **never post a reply equivalent to one already in the thread.** An unattended sweep runs again and again; a finding that was already answered gets no second answer.

## Two rules that carry most of the weight

**Claim only what you actually did — checks and fixes alike.** Writing "verified with `<command>`" when you didn't run it, or wording a reply as "Fixed in `<sha>`" before the fix exists, puts a fabricated citation under your name on a permanent record. Both are the same error. Until a fix is committed, write the reply in the future tense or hold it; if a check was impossible, say so — "I couldn't verify this locally because X" is honest and still useful. If you have already published such a claim, run the check for real and correct the comment, saying plainly what was wrong: a silent edit leaves anyone who read it misinformed.

**Know which revision you are reading before you cite `file:line`.** A local checkout is very often on some other branch, so line numbers, greps and file contents silently describe code that isn't in this PR. Cited line numbers that are ten lines off, or a count of "8 jobs" when the PR's own file makes it 9, destroy the credibility of an otherwise correct finding — especially when the wrong number ends up inside a published reply.

Unless your working tree is *on the PR's head commit*, read every file you intend to cite at the PR's SHA:

```bash
HEAD_SHA=$(gh api repos/$OWNER/$REPO/pulls/$PR --jq .head.sha)
gh api "repos/$OWNER/$REPO/contents/$PATH?ref=$HEAD_SHA" --jq '.content' | base64 -d
```

Do not reason your way out of this. "The only local commit touches unrelated files, so the rest must match" is the shortcut that produces wrong citations: it ignores everything the branch is *missing* from upstream. Comparing SHAs is cheap; being confidently ten lines off in a permanent comment is not.

## Output language

Everything you publish to GitHub — replies, commit messages, PR descriptions — is written in **English**, regardless of the language the user is speaking to you. The conversation with the user stays in their language; the PR is a shared artifact that outlives the conversation.

## Working on the fix vs. talking about it

You have autonomy to fix what is genuinely broken: apply the change, commit, push, report back. Stop and ask first when the fix would change public API or behaviour beyond the PR's stated scope, when it needs a product decision, or when the finding is right but several reasonable fixes exist and picking one is the author's call. The test is whether a reviewer would be surprised to see the change appear under this PR's title.

Prefer a fix scoped to the callsite over editing a shared helper. A helper often guards several other callers — changing it turns one finding into an unreviewed change to code nobody asked you to touch. If the shared fix really is the right one, say so explicitly and list what else it affects.

---

## Workflow

### 1. Identify the PR and sync your local checkout

If the user gave a URL or number, use it. Otherwise resolve it from the current branch:

```bash
gh pr list --head "$(git branch --show-current)" --json number,title,url,state
```

Then sync before doing anything else:

```bash
git fetch origin && git merge --ff-only "origin/$(git branch --show-current)"
```

Suggestions accepted through the GitHub web UI create real commits that exist only on the remote. Starting from a stale base means losing them, handing the user a conflict, or quoting a commit SHA that is wrong. If the fast-forward fails the branch has diverged — stop and tell the user rather than guessing at a merge strategy.

If you are analysing a PR on a branch you are not on, do not assume the working tree matches it. Read files at the PR's SHA instead.

### 2. Collect the unresolved threads

Comments live in three places and you need all three (`references/github-api.md` has the commands):

- **Issue comments** — the bot's summary, which carries the `Reviewed up to commit:` SHA, telling you how much of the PR has actually been reviewed.
- **Inline review comments** — the individual findings, anchored to a file and line.
- **Review threads via GraphQL** — the only source exposing `isResolved` and the `threadId` you need to resolve anything.

Skip resolved threads. Split the rest by author:

- A login ending in `[bot]` (e.g. `sftbot-pr-reviewer[bot]`) → **bot thread**: analyse, reply, resolve.
- A human login → **human thread**: analyse and reply, but **never resolve it**. Closing a person's thread takes away their chance to disagree with your answer.

A human comment is not always a finding. Authors annotate their own diffs to guide reviewers, and reviewers leave `suggestion` blocks that may already have been applied. Read what it actually asks for before deciding it needs a fix.

### 3. Verify each finding

Separate the finding's **premise** from its **conclusion** — a finding is often a true observation plus a wrong inference, and saying which is which is far more useful than "disagree".

The reviewer saw the diff. It usually did not see the provisioning script, the base framework, the CI workflow, or the running system — that blind spot is where most false positives live, and where your evidence comes from. Two questions cover most cases:

- **"X was deleted and now Y is missing" → who else provides Y?** Search the whole repo, especially the places a diff-reader never looks: `Makefile`s, bootstrap scripts, CI workflows, terraform. A deletion is often the second half of a migration whose first half already landed — `git log -S` on the destination file dates the move and gives you a SHA to cite. (For globally-named resources such as a `ClusterSecretStore` or a DNS record, duplication is itself the bug, so removing one is the fix.)
- **"This general rule is violated" → does the rule's precondition hold here?** Rules have scope. A doc that mandates a trait for *queued* jobs doesn't bind a job that is only ever `dispatchSync`'d; a window whose bounds are recomputed each run doesn't behave like a fixed one. Check the precondition against this code before applying the rule — and note that documentation records intent at the time it was written, so a finding backed only by a doc sentence may be citing something the code outgrew.

Cite things a reader can reproduce: a command and its real output, a `file:line` at the right revision, a commit SHA. Reasoning where you could have looked ("this should still work because the chart probably...") is not evidence.

Reach one of three verdicts: **correct** (needs a code change), **false positive** (the conclusion doesn't hold — needs evidence, not an opinion), or **correct but out of scope** (right observation, wrong PR; say where it belongs).

### 4. Apply the fixes, then commit and push

Do all the code changes first, then commit, then push — replies reference commit SHAs, so the commits must exist before you write them.

Respect the repo's conventions: read `CLAUDE.md` and `.claude/rules/` for commit format, ticket prefixes and style, and run whatever the project uses for linting and static analysis before pushing. If every finding was a false positive there is nothing to commit — don't manufacture an empty commit just to have something to push.

### 5. Reply to every thread you looked at

Lead with the verdict, back it with reproducible evidence, keep it short. A reply's job is to let a future reader understand the finding's fate without re-deriving it.

**Correct:**

```markdown
✅ Fixed in `<sha>`.

<Root cause in a sentence or two — what actually went wrong, not just what changed.>
```

**False positive:**

```markdown
❌ **False positive** — <one-line reason>.

**Evidence:**

1. <Fact with its source: file:line, commit SHA, or command output.>
2. <Command you ran and what it printed.>

<Why the premise was true but the conclusion doesn't follow, if that's the shape of it.>

**Feedback for the bot:** <what it should have checked, phrased as a rule that generalises.>
```

**Correct but out of scope:**

```markdown
⚠️ Valid, but out of scope for this PR — <why>.

<Where it should be handled: ticket, follow-up PR, or an explicit decision to leave it.>
```

The bot-feedback block is the reason the user is doing this — the replies get mined later to improve the reviewer. Aim it at the *class* of mistake: "it read the docs without checking who creates the resource — a `grep -rn` over `Makefile`s would have ruled it out" is reusable; "this is wrong" teaches nothing. Don't credit the bot with being right about something you just argued it got wrong; a reply that contradicts itself is worse than no feedback.

Post replies inside the thread, not as new top-level comments.

### 6. Resolve — bot threads only

Resolve every bot thread you replied to, whatever the verdict: the reply is the record, and leaving them open makes the PR look unaddressed. This needs the GraphQL `resolveReviewThread` mutation with the `threadId` from step 2 — the numeric comment id will not work.

Leave human threads open.

### 7. Wait for CI and the bot's next pass

```bash
gh pr checks "$PR" --watch
```

A CI failure is now yours: read the logs, fix, push, wait again.

Then work out whether another review pass is even coming. The bot re-reviews on push, and its summary records `Reviewed up to commit:`. If you pushed, a new pass is coming — wait for it, and new findings send you back to step 2. If you pushed nothing because everything was a false positive, **no new pass will fire**; say so explicitly rather than waiting for an event that never comes.

### 8. Report back

Tell the user, in their language: each finding and its verdict, the evidence for anything you refuted, the commits you pushed, and the CI and review state. Be explicit about anything left unresolved or out of scope — scaling the work down is their decision, not yours.

---

## Reference

`references/github-api.md` — the `gh` and GraphQL commands for listing threads, replying, editing and resolving.
