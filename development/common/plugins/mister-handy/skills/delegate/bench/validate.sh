#!/bin/bash
# validate.sh [task-id...]: each check.sh must fail on its base and pass on its merged commit; writes tasks/<id>/tests (base passed, total)
set -u
. "$(dirname "$0")/lib.sh"
[ $# -gt 0 ] || set -- $(ls "$bench/tasks")
bad=0
for task in "$@"; do
  tdir=$bench/tasks/$task
  merged=$(sed -n 's/^hidden \([0-9a-f]\{40\}\) .*/\1/p' "$tdir/check.sh")
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/bench-validate.XXXXXX")
  for side in base merged; do
    repo=$tmp/$side
    sha=$(cat "$tdir/base"); [ "$side" = merged ] && sha=$merged
    git init -q -b main "$repo" && git -C "$repo" fetch -q --no-tags "$BENCH_SRC" "$sha" && git -C "$repo" reset -q --hard FETCH_HEAD
    [ "$side" = base ] && [ -x "$tdir/prepare.sh" ] && "$tdir/prepare.sh" "$repo"
    out=$("$tdir/check.sh" "$repo" 2>&1); code=$?
    score=$(grep '^BENCH-SCORE ' <<<"$out" | tail -1 | cut -d' ' -f2-)
    echo "$task $side exit=$code score=${score:-none}"
    [ "$side" = base ] && base_passed=${score%% *}
    if [ "$side" = base ] && [ "$code" -eq 0 ]; then echo "  base passes: the check does not discriminate"; bad=1; fi
    if [ "$side" = merged ]; then
      if [ "$code" -ne 0 ]; then echo "  merged fails:"; tail -15 <<<"$out" | sed 's/^/    /'; bad=1
      else echo "${base_passed:-0} ${score#* }" >"$tdir/tests"; fi
    fi
  done
  rm -rf "$tmp"
done
exit "$bad"
