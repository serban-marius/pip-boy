#!/bin/bash
# check.sh <repo>: copies the merged commit's tests into <repo> and runs them; exit 0 = pass
repo=${1:?usage: check.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
hidden b61cbf56c7a1a257e5aaff12030e1adfdb869bce development/common/plugins/overseer/hooks/overseer.test.sh || exit 2
run_bash_test development/common/plugins/overseer/hooks/overseer.test.sh
