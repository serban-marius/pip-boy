#!/usr/bin/env bash
# Checks the gh/git shims: blocked calls exit 86 without reaching the network,
# allowed calls reach the real binary. Run on the Pi after deploy.
set -u
fail=0
blocked() { "$@" >/dev/null 2>&1; [ $? -eq 86 ] || { echo "NOT blocked: $*"; fail=1; }; }
allowed() { "$@" >/dev/null 2>&1; [ $? -ne 86 ] || { echo "wrongly blocked: $*"; fail=1; }; }

blocked gh pr merge 1 -R serban-marius/goldclaw
blocked gh -R serban-marius/goldclaw pr close 1
blocked gh pr edit 1 --title x
blocked gh issue close 1
blocked gh repo delete serban-marius/goldclaw --yes
blocked gh api -X PUT repos/serban-marius/goldclaw/pulls/1/merge
blocked gh api --method DELETE repos/serban-marius/goldclaw/git/refs/heads/x
blocked gh api -XPATCH repos/serban-marius/goldclaw/pulls/1 -f state=closed
blocked gh api graphql -f query='mutation { mergePullRequest(input:{pullRequestId:"x"}) { clientMutationId } }'
blocked git push --force origin main
blocked git push -f origin main
blocked git push -uf origin main
blocked git push --force-with-lease origin main
blocked git push origin --delete feature
blocked git push origin :feature
blocked git push origin +main

allowed gh api user --jq .login
allowed gh pr view 11 -R serban-marius/pip-boy --json number
allowed gh api -X DELETE notifications/threads/0
allowed gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:"x"}) { thread { id } } }'
allowed git --version
allowed git -C "$HOME/repos/pip-boy" status --short
allowed git -C "$HOME/repos/pip-boy" push --dry-run origin HEAD

[ "$fail" = 0 ] && echo "shims ok" || exit 1
