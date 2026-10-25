#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
marketplace=$root/.claude-plugin/marketplace.json
failed=0
registered=$(mktemp)
trap 'rm -f "$registered"' EXIT

report() {
  printf 'marketplace: %s\n' "$*" >&2
  failed=1
}

if ! jq -e . "$marketplace" >/dev/null 2>&1; then
  printf 'marketplace: invalid JSON: %s\n' "$marketplace" >&2
  exit 1
fi

if ! jq -e '.plugins | type == "array"' "$marketplace" >/dev/null; then
  printf 'marketplace: .plugins is not an array: %s\n' "$marketplace" >&2
  exit 1
fi

while IFS=$'\x1f' read -r name version source; do
  dir=${source#./}
  dir=${dir%/}
  printf '%s\n' "$dir" >>"$registered"
  manifest=$root/$dir/.claude-plugin/plugin.json
  if [ ! -f "$manifest" ]; then
    report "$name: missing $dir/.claude-plugin/plugin.json"
    continue
  fi
  if ! jq -e . "$manifest" >/dev/null 2>&1; then
    report "$name: invalid JSON in $dir/.claude-plugin/plugin.json"
    continue
  fi
  actual_name=$(jq -r '.name // empty' "$manifest")
  actual_version=$(jq -r '.version // empty' "$manifest")
  [ "$actual_name" = "$name" ] || report "$name: plugin.json name is '$actual_name'"
  [ "$actual_version" = "$version" ] || report "$name: plugin.json version is '$actual_version', marketplace says '$version'"
done < <(jq -r '.plugins[] | select(.source | type == "string") | [(.name // ""), (.version // ""), .source] | join("\u001f")' "$marketplace")

while IFS= read -r manifest; do
  dir=${manifest%/.claude-plugin/plugin.json}
  grep -Fxq -- "$dir" "$registered" || report "unregistered plugin: $dir"
done < <(git -C "$root" ls-files --cached --others --exclude-standard '*/plugins/*/.claude-plugin/plugin.json' '*/external_plugins/*/.claude-plugin/plugin.json')

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'marketplace ok: %s local plugins\n' "$(wc -l <"$registered" | tr -d ' ')"
