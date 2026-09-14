# Cheatsheet: gh CLI / GitHub API for addressing review comments

All snippets assume `OWNER`, `REPO`, `PR` are set. Most examples below use
`softonic-development/projection` shapes but nothing here is org-specific.

## Resolve the PR from the current branch

```bash
gh pr list --head "$(git branch --show-current)" \
  --json number,title,url,state,headRefOid
```

## Sync local with remote before touching anything

```bash
git fetch origin
git merge --ff-only "origin/$(git branch --show-current)"
```

If the fast-forward fails the branch has diverged — stop and report, don't improvise a merge.

Note: a branch created locally and pushed without `-u` has no upstream, so a bare
`git pull` fails with "no tracking information". The explicit
`fetch` + `merge --ff-only origin/<branch>` above works regardless.

## Read the state of the PR

```bash
gh pr view "$PR" --json title,state,mergeable,mergeStateStatus,reviewDecision,headRefOid
```

`reviewDecision` is `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED` / null. A bot that
posts findings as a `COMMENTED` review does **not** set `CHANGES_REQUESTED`, even if its
summary comment says "Changes requested" — so don't infer the blocking state from the text.

## Collect comments — three sources, all needed

### 1. Issue comments (the bot's summary, carries the reviewed-up-to SHA)

```bash
gh pr view "$PR" --json comments \
  --jq '.comments[] | {author: .author.login, createdAt, body}'
```

### 2. Inline review comments (the individual findings)

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/comments" --paginate \
  --jq '.[] | {id, user: .user.login, path, line, in_reply_to_id, body}'
```

The `id` here is what you reply to and what you PATCH. It is **not** what you resolve with.

### 3. Review threads via GraphQL (resolved state + thread ids)

This is the only source that exposes `isResolved` and the `threadId`:

```bash
gh api graphql -f query='
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          path
          comments(first: 10) { nodes { author { login } databaseId body } }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
         | {id, isResolved, path,
            authors: [.comments.nodes[].author.login],
            first_body: .comments.nodes[0].body[0:100]}'
```

`OWNER`, `REPO` and `PR` must be interpolated into the query string — GraphQL literals here,
not shell variables inside single quotes. Build the query with double quotes or a heredoc.

## Reply inside a thread

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
  -f body="$BODY" --jq '.html_url'
```

`$COMMENT_ID` is the numeric `id` of the **first** comment in the thread. This keeps the
conversation threaded; a new top-level comment would detach it from the finding.

For multi-line bodies with backticks and code fences, pass the text through a file to avoid
shell mangling:

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
  -F body=@reply.md --jq '.html_url'
```

## Edit a reply you already posted

Note the different path — `pulls/comments/{id}`, without the PR number:

```bash
gh api -X PATCH "repos/$OWNER/$REPO/pulls/comments/$COMMENT_ID" \
  -f body="$CORRECTED_BODY" --jq '.html_url'
```

Use this to correct a published claim you couldn't actually back. Say in the corrected text
what changed, so anyone who read the original isn't left with the wrong version.

## Resolve a thread (bot threads only)

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "PRRT_kwDO..."}) {
    thread { id isResolved }
  }
}' --jq '.data.resolveReviewThread.thread'
```

The `threadId` is the `id` from the `reviewThreads` query (`PRRT_...`), **not** the numeric
comment id. To reopen one: `unresolveReviewThread` with the same input shape.

## CI

```bash
gh pr checks "$PR"           # snapshot
gh pr checks "$PR" --watch   # block until they finish
```

Failure logs for a specific run:

```bash
gh run view "$RUN_ID" --log-failed
```

## Common errors

- **`Resource not accessible by integration`** on resolve — the token lacks write access to
  the PR, or the thread belongs to a different repo than the one in the query.
- **`Could not resolve to a node with the global id`** — a numeric comment id was passed
  where a `PRRT_` thread id was expected.
- **Reply lands as a new top-level comment** — `$COMMENT_ID` pointed at a reply rather than
  the first comment of the thread.
- **Backticks executing in the shell** — the body was passed in double quotes; use single
  quotes or `-F body=@file`.
