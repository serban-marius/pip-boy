#!/bin/bash
# check.sh <repo>: copies the merged commit's tests into <repo> and runs them; exit 0 = pass
repo=${1:?usage: check.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
hidden 57865f5bccdfa6fdbe95d45aba7d2c01b9fe2135 development/common/plugins/holotape/skills/jira-write/bin/test_jira_preview.py || exit 2
run_unittest development/common/plugins/holotape/skills/jira-write/bin/test_jira_preview.py
