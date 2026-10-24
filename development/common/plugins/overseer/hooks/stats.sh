#!/usr/bin/env bash

stat_files() {
  local f
  _files=()
  for f in "$1"/overseer/*.log "$1"/worktrees/*/overseer/*.log; do [ -f "$f" ] && _files+=("$f"); done
}
stat_counts() {
  awk '$2=="block"{n[$3]++} END{for (r in n) print r, n[r]}' "$@" | sort -k2,2nr -k1,1
}
stat_escalations() { awk '$2=="escalate"{n++} END{print n+0}' "$@"; }
stat_deltas() {
  awk -v map="$RULE_MODES" '
    function mode(r,  n,i,a,p) { n=split(map,a," "); for (i=1;i<=n;i++) { p=index(a[i],":"); if (r ~ substr(a[i],p+1)) return substr(a[i],1,p-1) }; return "" }
    function bucket(m) { return (m=="pre-edit" || m=="pre-bash") ? "pre" : m }
    FNR==1 { split("", pending) }
    $2=="block" { m=bucket(mode($3)); if (m!="" && !(m in pending)) pending[m]=$1; next }
    $2=="pass" { k=bucket($3); if (k in pending) { d=$1-pending[k]; if (d>=0) print d; delete pending[k] } }
  ' "$@" | sort -n
}
stat_median() {
  if [ -n "$1" ]; then
    awk 'NF{a[NR]=$1} END{if(NR%2) print a[(NR+1)/2]"s"; else printf "%.0fs\n",(a[NR/2]+a[NR/2+1])/2}' <<<"$1"
  else
    echo -
  fi
}
print_counts() {
  echo "blocks:"
  if [ -n "$1" ]; then awk '{printf "  %-24s %d\n", $1, $2}' <<<"$1"; else echo "  none"; fi
}
stats() {
  local base=$1 counts esc deltas
  echo "overseer stats ($base/overseer)"
  stat_files "$base"
  if [ "${#_files[@]}" -eq 0 ]; then echo "blocks: none"; echo "escalations: 0"; echo "median unblock: -"; return 0; fi
  counts=$(stat_counts "${_files[@]}")
  esc=$(stat_escalations "${_files[@]}")
  deltas=$(stat_deltas "${_files[@]}")
  print_counts "$counts"
  echo "escalations: $esc"
  echo "median unblock: $(stat_median "$deltas")"
}
