#!/usr/bin/env bash
# pr-snapshot.sh — one JSON snapshot of a pull request's *current* state:
# head SHA, checks on that SHA, review threads (with resolution/outdated state
# and root-author account type), reviews and issue comments.
# Usage: pr-snapshot.sh <owner/repo> <pr-number>
# Requires: gh (authenticated), jq
set -euo pipefail

repo="${1:?usage: pr-snapshot.sh <owner/repo> <pr-number>}"
num="${2:?usage: pr-snapshot.sh <owner/repo> <pr-number>}"
owner="${repo%%/*}"
name="${repo##*/}"

query='query($owner:String!,$name:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$name){ pullRequest(number:$number){
    number url state isDraft updatedAt headRefOid headRefName baseRefName reviewDecision mergeable
    author{login __typename}
    commits(last:1){nodes{commit{oid statusCheckRollup{state contexts(first:100){nodes{__typename
      ... on CheckRun{name status conclusion detailsUrl}
      ... on StatusContext{context state targetUrl}}}}}}}
    reviewThreads(first:50,after:$cursor){pageInfo{hasNextPage endCursor} nodes{
      id isResolved isOutdated path line originalLine
      comments(first:100){nodes{id databaseId author{login __typename} body createdAt outdated commit{oid} replyTo{id}}}}}
    comments(last:100){nodes{id databaseId author{login __typename} body createdAt}}
    reviews(last:100){nodes{id author{login __typename} state body submittedAt commit{oid}}}
  }}}'

fetch() { # $1 = cursor or empty
  local args=(-f query="$query" -F owner="$owner" -F name="$name" -F number="$num")
  [ -n "${1:-}" ] && args+=(-f cursor="$1")
  gh api graphql "${args[@]}"
}

first="$(fetch "")"
pr="$(jq '.data.repository.pullRequest' <<<"$first")"
[ "$pr" != "null" ] || { echo "PR $repo#$num not found" >&2; exit 1; }
threads="$(jq '.reviewThreads.nodes' <<<"$pr")"
cursor="$(jq -r '.reviewThreads.pageInfo | select(.hasNextPage) | .endCursor' <<<"$pr")"
while [ -n "$cursor" ]; do # ponytail: PRs with >50 review threads paginate here
  page="$(fetch "$cursor" | jq '.data.repository.pullRequest.reviewThreads')"
  threads="$(jq -n --argjson a "$threads" --argjson b "$(jq '.nodes' <<<"$page")" '$a + $b')"
  cursor="$(jq -r '.pageInfo | select(.hasNextPage) | .endCursor' <<<"$page")"
done

jq -n --argjson pr "$pr" --argjson threads "$threads" '
  def actor: if . == null then {login: null, type: "Unknown"} else {login: .login, type: .__typename} end;
  ($pr.commits.nodes[0].commit.statusCheckRollup) as $roll |
  {
    snapshotAt: (now | todate),
    pr: {
      number: $pr.number, url: $pr.url, state: $pr.state, isDraft: $pr.isDraft,
      author: ($pr.author | actor), headRefOid: $pr.headRefOid, headRefName: $pr.headRefName,
      baseRefName: $pr.baseRefName, reviewDecision: $pr.reviewDecision, mergeable: $pr.mergeable,
      updatedAt: $pr.updatedAt
    },
    checks: {
      state: ($roll.state // "NONE"),
      contexts: [ ($roll.contexts.nodes // [])[] |
        if .__typename == "CheckRun"
        then {name: .name, status: .status, conclusion: .conclusion, url: .detailsUrl}
        else {name: .context, status: "COMPLETED", conclusion: .state, url: .targetUrl} end ]
    },
    reviewThreads: [ $threads[] | {
      id, isResolved, isOutdated, path, line, originalLine,
      rootAuthor: (.comments.nodes[0].author | actor),
      comments: [ .comments.nodes[] | {
        id, databaseId, author: (.author | actor), body, createdAt, outdated,
        commit: .commit.oid, replyTo: .replyTo.id } ]
    } ],
    reviews: [ $pr.reviews.nodes[] | {id, author: (.author | actor), state, body, submittedAt, commit: .commit.oid} ],
    issueComments: [ $pr.comments.nodes[] | {id, databaseId, author: (.author | actor), body, createdAt} ]
  }'
