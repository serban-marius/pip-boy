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

fresh; upstream u1; hook "$tmp/r"
grep -q u1 "$tmp/r/a.txt" && ok "on clean main it pulls" || bad "on clean main it pulls"

fresh; git -C "$tmp/r" checkout -qb feat/x; echo f >"$tmp/r/f.txt"; git -C "$tmp/r" add .; git -C "$tmp/r" commit -qm f; hook "$tmp/r"
[ "$(git -C "$tmp/r" branch --show-current)" = main ] && ok "clean feature branch in the main checkout goes back to main" || bad "clean feature branch in the main checkout goes back to main"

fresh; git -C "$tmp/r" checkout -qb feat/dirty; echo dirty >>"$tmp/r/a.txt"; hook "$tmp/r"
{ [ "$(git -C "$tmp/r" branch --show-current)" = feat/dirty ] && grep -q dirty "$tmp/r/a.txt" && [ -z "$(git -C "$tmp/r" stash list)" ]; } \
  && ok "dirty feature branch: no switch, no stash, changes stay" || bad "dirty feature branch: no switch, no stash, changes stay"

fresh; echo dirty >>"$tmp/r/a.txt"; upstream u2; hook "$tmp/r"
{ grep -q dirty "$tmp/r/a.txt" && [ -z "$(git -C "$tmp/r" stash list)" ]; } && ok "dirty main: changes untouched, no stash" || bad "dirty main: changes untouched, no stash"

fresh; git -C "$tmp/r" worktree add -q -b feat/wt "$tmp/wt" 2>/dev/null; hook "$tmp/wt"
[ "$(git -C "$tmp/wt" branch --show-current)" = feat/wt ] && ok "linked worktree keeps its branch" || bad "linked worktree keeps its branch"

hook "$tmp" && ok "outside a repo exits 0" || bad "outside a repo exits 0"

msg=$(out "$tmp/r")
[ -n "$msg" ] && [ "$(printf '%s\n' "$msg" | wc -l | tr -d ' ')" -eq 1 ] && ok "prints one non-empty line" || bad "prints one non-empty line"

[ "$fails" -eq 0 ] && echo "all green" || { echo "$fails failed"; exit 1; }
