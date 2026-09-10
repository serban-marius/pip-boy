#!/usr/bin/env bash
# inbox-snapshot.sh — every thread in the authenticated user's GitHub inbox
# (read and unread; "done" threads are gone), enriched for pull requests with
# state, author account type, the user's latest review and CI state, plus a
# rule-based verdict:
#   done -> safe to mark as done (rule says why)
#   keep -> needs a human (pending review on a human PR, mention, assignment...)
# Usage: inbox-snapshot.sh [login]      (prints a JSON array)
# Requires: gh (authenticated, repo scope), jq
set -euo pipefail
login="${1:-$(gh api user --jq .login)}"

notifs="$(gh api --paginate 'notifications?all=true&per_page=100' | jq -s 'add // []')"

# Enrich pull requests in batches of 40 through one GraphQL query per batch.
# ponytail: issues are not enriched (none in this inbox today); add an Issue
# branch here if "closed issue" notifications start piling up.
prs="$(jq -c '[.[] | select(.subject.type=="PullRequest") |
  {id, owner: .repository.owner.login, name: .repository.name, number: (.subject.url|split("/")|last|tonumber)}]' <<<"$notifs")"
enriched='{}'
while read -r chunk; do
  [ -n "$chunk" ] || continue
  fields="$(jq -r '.[] | "t\(.id): repository(owner:\"\(.owner)\",name:\"\(.name)\"){pullRequest(number:\(.number)){state merged isDraft author{login __typename} reviews(last:1,author:$login){nodes{state}} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}"' <<<"$chunk" | tr '\n' ' ')"
  page="$(gh api graphql -F login="$login" -f query="query(\$login:String!){ $fields }" 2>/dev/null | jq '.data // {}' || echo '{}')"
  enriched="$(jq -n --argjson a "$enriched" --argjson b "$page" '$a + $b')"
done < <(jq -c '_nwise(40)' <<<"$prs")

jq -n --argjson n "$notifs" --argjson e "$enriched" '
  def actor: if . == null then {login: null, type: "Unknown"} else {login: .login, type: .__typename} end;
  [ $n[] | . as $t | ($e["t" + $t.id].pullRequest // null) as $p |
    { threadId: $t.id, reason: $t.reason, unread: $t.unread, updatedAt: $t.updated_at,
      repo: $t.repository.full_name, type: $t.subject.type, title: $t.subject.title,
      url: ($t.subject.url | if . then sub("api.github.com/repos"; "github.com") | sub("/pulls/"; "/pull/") else null end),
      pr: (if $p then { state: (if $p.merged then "MERGED" else $p.state end), isDraft: $p.isDraft,
                        author: ($p.author | actor), myLastReview: ($p.reviews.nodes[0].state // null),
                        checks: ($p.commits.nodes[0].commit.statusCheckRollup.state // "NONE") } else null end) }
    | . + (
        if (.reason | IN("mention", "assign", "team_mention")) then {verdict: "keep", rule: "direct \(.reason)"}
        elif .pr != null and .pr.state != "OPEN" then {verdict: "done", rule: "pr \(.pr.state | ascii_downcase)"}
        elif (.reason | IN("author", "ci_activity", "push", "subscribed")) then {verdict: "done", rule: "noise \(.reason)"}
        elif .reason == "review_requested" and .pr != null and .pr.author.type == "Bot" then {verdict: "done", rule: "bot pr"}
        elif .reason == "review_requested" and .pr != null and .pr.myLastReview == "APPROVED" then {verdict: "done", rule: "already approved"}
        else {verdict: "keep", rule: "needs you"} end)
  ]'
