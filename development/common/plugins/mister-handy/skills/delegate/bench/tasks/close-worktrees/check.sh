#!/bin/bash
# check.sh <repo>: copies the merged commit's tests into <repo> and runs them; exit 0 = pass
repo=${1:?usage: check.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
hidden 9788f72162baccaddd25204f1c5c831d6d711847 development/common/plugins/mister-handy/skills/delegate/bin/delegate.test.sh || exit 2
run_bash_test development/common/plugins/mister-handy/skills/delegate/bin/delegate.test.sh
