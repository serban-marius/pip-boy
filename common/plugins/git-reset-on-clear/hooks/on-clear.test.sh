#!/usr/bin/env bash
set -u
for name in $(compgen -v GIT_CONFIG_ 2>/dev/null); do unset "$name"; done
here=$(cd "$(dirname "$0")" && pwd)
P=$(cd "$here/.." && pwd)
S=$here/on-clear.sh
[ -f "$S" ] || { echo "run from the worktree root"; exit 1; }
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

jq -e '.hooks.SessionStart[] | select(.matcher == "clear") | .hooks[] | select((.args // [] | join(" ") | test("CLAUDE_PLUGIN_ROOT.*/hooks/on-clear.sh")) or (.command | test("CLAUDE_PLUGIN_ROOT.*/hooks/on-clear.sh")))' "$P/hooks/hooks.json" >/dev/null 2>&1 \
  && ok "hooks.json wires SessionStart clear to on-clear.sh" || bad "hooks.json wires SessionStart clear to on-clear.sh"

origin=$tmp/origin.git
git init -q --bare -b main "$origin"
seed=$tmp/seed; git clone -q "$origin" "$seed" 2>/dev/null
git -C "$seed" config user.email t@t; git -C "$seed" config user.name t
echo a >"$seed/a.txt"; git -C "$seed" add .; git -C "$seed" commit -qm init; git -C "$seed" push -q origin HEAD:main
fresh() { rm -rf "$tmp/r"; git clone -q "$origin" "$tmp/r"; git -C "$tmp/r" config user.email t@t; git -C "$tmp/r" config user.name t; }
upstream() { echo "$1" >>"$seed/a.txt"; git -C "$seed" commit -qam "$1"; git -C "$seed" push -q origin HEAD:main; }
hook() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 bash "$S" </dev/null >/dev/null 2>&1); }
out() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 bash "$S" </dev/null 2>/dev/null); }
one_line() { [ -n "$1" ] && [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" -eq 1 ]; }

fresh; upstream u1; msg=$(out "$tmp/r")
{ grep -q u1 "$tmp/r/a.txt" && one_line "$msg" && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: pulled main'; } \
  && ok "on clean main it pulls and says so in one line" || bad "on clean main it pulls and says so in one line"

fresh; git -C "$tmp/r" checkout -qb feat/x; echo f >"$tmp/r/f.txt"; git -C "$tmp/r" add .; git -C "$tmp/r" commit -qm f
msg=$(out "$tmp/r")
{ [ "$(git -C "$tmp/r" branch --show-current)" = main ] && one_line "$msg" && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: switched feat/x -> main'; } \
  && ok "clean feature branch in the main checkout goes back to main in one line" || bad "clean feature branch in the main checkout goes back to main in one line"

fresh; git -C "$tmp/r" checkout -qb feat/y; echo y >"$tmp/r/y.txt"; git -C "$tmp/r" add .; git -C "$tmp/r" commit -qm y
upstream u3
msg=$(out "$tmp/r")
{ [ "$(git -C "$tmp/r" branch --show-current)" = main ] && ! grep -q u3 "$tmp/r/a.txt" && one_line "$msg" \
  && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: switched feat/y -> main'; } \
  && ok "switch does not pull afterwards" || bad "switch does not pull afterwards"

fresh; git -C "$tmp/r" checkout -qb feat/dirty; echo dirty >>"$tmp/r/a.txt"
msg=$(out "$tmp/r")
{ [ "$(git -C "$tmp/r" branch --show-current)" = feat/dirty ] && grep -q dirty "$tmp/r/a.txt" && [ -z "$(git -C "$tmp/r" stash list)" ] \
  && one_line "$msg" && printf '%s\n' "$msg" | grep -q "git-reset-on-clear: working tree has changes; left it alone"; } \
  && ok "dirty feature branch: no switch, no stash, changes stay, one-line notice" || bad "dirty feature branch: no switch, no stash, changes stay, one-line notice"

fresh; echo dirty >>"$tmp/r/a.txt"; upstream u2
msg=$(out "$tmp/r")
{ [ "$(git -C "$tmp/r" branch --show-current)" = main ] && grep -q dirty "$tmp/r/a.txt" && [ -z "$(git -C "$tmp/r" stash list)" ] \
  && one_line "$msg" && printf '%s\n' "$msg" | grep -q "git-reset-on-clear: working tree has changes; left it alone"; } \
  && ok "dirty main: changes untouched, no stash, one-line notice" || bad "dirty main: changes untouched, no stash, one-line notice"

fresh; git -C "$tmp/r" checkout -qb feat/elsewhere
git -C "$tmp/r" worktree add -q -b feat/wt "$tmp/wt" 2>/dev/null
msg=$(out "$tmp/wt")
{ [ -d "$tmp/wt" ] && [ "$(git -C "$tmp/wt" branch --show-current)" = feat/wt ] && one_line "$msg" \
  && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: linked worktree; left it alone'; } \
  && ok "linked worktree keeps its branch even though main is available to switch to" || bad "linked worktree keeps its branch even though main is available to switch to"

fresh; git -C "$tmp/r" checkout -q --detach; before=$(git -C "$tmp/r" rev-parse HEAD)
msg=$(out "$tmp/r")
{ [ -z "$(git -C "$tmp/r" branch --show-current)" ] && [ "$(git -C "$tmp/r" rev-parse HEAD)" = "$before" ] \
  && one_line "$msg" && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: detached HEAD; left it alone'; } \
  && ok "detached HEAD stays put with a one-line notice" || bad "detached HEAD stays put with a one-line notice"

origin_m=$tmp/origin-master.git
git init -q --bare -b master "$origin_m"
seed_m=$tmp/seed-master; git clone -q "$origin_m" "$seed_m" 2>/dev/null
git -C "$seed_m" config user.email t@t; git -C "$seed_m" config user.name t
echo m >"$seed_m/m.txt"; git -C "$seed_m" add .; git -C "$seed_m" commit -qm init; git -C "$seed_m" push -q origin HEAD:master
rm -rf "$tmp/rm"; git clone -q "$origin_m" "$tmp/rm"; git -C "$tmp/rm" config user.email t@t; git -C "$tmp/rm" config user.name t
git -C "$tmp/rm" remote set-head origin -d >/dev/null 2>&1
git -C "$tmp/rm" checkout -qb feat/m
msg=$(out "$tmp/rm")
{ [ "$(git -C "$tmp/rm" branch --show-current)" = master ] && ! git -C "$tmp/rm" symbolic-ref -q refs/remotes/origin/HEAD && one_line "$msg" \
  && printf '%s\n' "$msg" | grep -q 'git-reset-on-clear: switched feat/m -> master'; } \
  && ok "falls back to master when origin/HEAD is absent" || bad "falls back to master when origin/HEAD is absent"

hook "$tmp" && ok "outside a repo exits 0" || bad "outside a repo exits 0"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
