#!/bin/bash
# prepare.sh <repo>: the jira-write docs and spec 001 land first, the script is the task
repo=${1:?usage: prepare.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
P=development/common/plugins/holotape
hidden b2cace507b2ae36da1639a3275e830e33fee35a2 .claude-plugin/marketplace.json .gitignore \
  $P/.claude-plugin/plugin.json $P/README.md $P/skills/jira-write/SKILL.md \
  $P/skills/jira-write/references/catalogue.md $P/skills/jira-write/references/formatting.md \
  $P/skills/jira-write/references/templates.md specs/001-jira-preview/spec.md || exit 1
git -C "$repo" add -A && git -C "$repo" commit -qm "docs(holotape): jira-write skill docs and spec 001-jira-preview"
