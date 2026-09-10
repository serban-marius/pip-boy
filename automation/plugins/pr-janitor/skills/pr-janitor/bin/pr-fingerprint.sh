#!/usr/bin/env bash
# pr-fingerprint.sh — one line per open, non-draft PR authored by the given
# login (default: the authenticated user): "<owner/repo>#<n> <head> <updatedAt> <checks> unresolved=<k>".
# The output only changes when something the janitor cares about changed, so
# it can be compared between runs to decide whether to wake the agent.
# Usage: pr-fingerprint.sh [login]
set -euo pipefail
login="${1:-$(gh api user --jq .login)}"
gh api graphql -f q="is:pr is:open draft:false author:$login" -f query='
  query($q:String!){ search(query:$q, type:ISSUE, first:100){ nodes{ ... on PullRequest{
    repository{nameWithOwner} number updatedAt headRefOid
    commits(last:1){nodes{commit{statusCheckRollup{state}}}}
    reviewThreads(first:100){nodes{isResolved}}
  }}}}' \
| jq -r '.data.search.nodes[] | select(.number != null) |
    "\(.repository.nameWithOwner)#\(.number) \(.headRefOid[0:12]) \(.updatedAt) \(.commits.nodes[0].commit.statusCheckRollup.state // "NONE") unresolved=\([.reviewThreads.nodes[] | select(.isResolved|not)] | length)"' \
| sort
