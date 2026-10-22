#!/bin/bash
# Sourced by run.sh and tasks/*/check.sh.

bench=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BENCH_SRC=${BENCH_SRC:-$(git -C "$bench" rev-parse --show-toplevel)}

with_timeout() {
  perl -e '
    my $t = shift; my $pid = fork // die "fork: $!";
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; waitpid($pid, 0); exit 124 };
    alarm $t; waitpid($pid, 0); my $c = $?; kill "TERM", -$pid;
    exit($c & 127 ? 128 + ($c & 127) : $c >> 8)' "$@"
}

hidden() {
  local sha=$1 path; shift
  for path; do
    mkdir -p "$repo/$(dirname "$path")"
    git -C "$BENCH_SRC" show "$sha:$path" >"$repo/$path" || return 1
  done
}

score() { echo "BENCH-SCORE $1 $2"; }

run_bash_test() {
  local out code
  out=$(cd "$repo" && with_timeout 300 bash "$1" 2>&1); code=$?
  printf '%s\n' "$out"
  score "$(grep -c '^ok ' <<<"$out")" "$(grep -cE '^(ok|FAIL) ' <<<"$out")"
  return "$code"
}

run_unittest() {
  local out code total bad
  out=$(cd "$repo/$(dirname "$1")" && with_timeout 300 python3 "$(basename "$1")" -v 2>&1); code=$?
  printf '%s\n' "$out"
  total=$(sed -n 's/^Ran \([0-9]*\) tests\{0,1\}.*/\1/p' <<<"$out" | tail -1)
  bad=$(grep -cE '^(FAIL|ERROR): ' <<<"$out")
  score "$(( ${total:-0} - bad < 0 ? 0 : ${total:-0} - bad ))" "${total:-0}"
  return "$code"
}

pipeline_brief() {
  awk -v risk="$(cat "$2/risk")" -v accept="$2/accept" '
    NR == 1 { print; print ""; print "Risk: " risk; next }
    $0 == "## Acceptance" { print "## Done when"; next }
    $0 == "## Rules" && !done { print "## Acceptance"; while ((getline l < accept) > 0) print "- `" l "`"; print ""; done = 1 }
    { print }' "$1"
}
