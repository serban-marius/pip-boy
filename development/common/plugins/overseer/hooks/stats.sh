#!/usr/bin/env bash

stats() {
  local base=$1 counts esc deltas med files=() f
  echo "overseer stats ($base/overseer)"
  for f in "$base"/overseer/*.log "$base"/worktrees/*/overseer/*.log; do [ -f "$f" ] && files+=("$f"); done
  if [ "${#files[@]}" -eq 0 ]; then echo "blocks: none"; echo "escalations: 0"; echo "median unblock: -"; return 0; fi
  counts=$(awk '$2=="block"{n[$3]++} END{for (r in n) print r, n[r]}' "${files[@]}" | sort -k2,2nr -k1,1)
  esc=$(awk '$2=="escalate"{n++} END{print n+0}' "${files[@]}")
  deltas=$(awk -v map="$RULE_MODES" '
    function mode(r,  n,i,a,p) {
      n=split(map,a," ")
      for (i=1;i<=n;i++) { p=index(a[i],":"); if (r ~ substr(a[i],p+1)) return substr(a[i],1,p-1) }
      return ""
    }
    FNR==1 { split("", pending) }
    $2=="block" {
      m=mode($3)
      if (m!="" && !(m in pending)) pending[m]=$1
      next
    }
    $2=="pass" {
      if ($3 in pending) {
        d=$1-pending[$3]
        if (d>=0) print d
        delete pending[$3]
      }
    }
  ' "${files[@]}" | sort -n)
  echo "blocks:"
  if [ -n "$counts" ]; then awk '{printf "  %-24s %d\n", $1, $2}' <<<"$counts"; else echo "  none"; fi
  echo "escalations: $esc"
  if [ -n "$deltas" ]; then
    med=$(awk 'NF{a[NR]=$1} END{if(NR%2) print a[(NR+1)/2]"s"; else printf "%.0fs\n",(a[NR/2]+a[NR/2+1])/2}' <<<"$deltas")
  else
    med=-
  fi
  echo "median unblock: $med"
}
