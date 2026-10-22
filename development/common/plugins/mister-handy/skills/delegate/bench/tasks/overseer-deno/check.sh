#!/bin/bash
# check.sh <repo>: copies the merged commit's tests into <repo> and runs them; exit 0 = pass
repo=${1:?usage: check.sh <repo dir>}
. "$(dirname "$0")/../../lib.sh"
hidden f7a79612eb9a78b17ed34404b9abe39a68ec7a68 development/common/plugins/overseer/hooks/overseer.test.sh || exit 2
run_bash_test development/common/plugins/overseer/hooks/overseer.test.sh
