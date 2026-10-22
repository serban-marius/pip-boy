#!/bin/bash
# check.sh <repo>: copies the merged commit's tests into <repo> and runs them; exit 0 = pass
repo=${1:?usage: check.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
hidden b2cace507b2ae36da1639a3275e830e33fee35a2 development/common/plugins/holotape/skills/jira-write/bin/test_jira_preview.py || exit 2
run_unittest development/common/plugins/holotape/skills/jira-write/bin/test_jira_preview.py
