#!/usr/bin/env bash

set -u
mode=${1:-}

abspath_from() {
  local base=$1 p=$2 part out=()
  case "$p" in /*) ;; *) p=$base/$p ;; esac
  local IFS=/
  for part in $p; do
    case "$part" in
      ''|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  if [ ${#out[@]} -gt 0 ]; then printf '/%s' "${out[@]}"; else printf '/'; fi
}
abspath() { abspath_from "$PWD" "$1"; }

strip_quotes() { local p=$1; p=${p#[\"\']}; p=${p%[\"\']}; printf '%s' "$p"; }
strip_heredocs() {
  awk '
    {
      line=$0
      if (pending != "") {
        if (line == pending || line ~ ("^[ \t]*" pending "[ \t]*$")) pending=""
        next
      }
      if (match(line, /<<-?[ \t]*[\"\047]?[A-Za-z_][A-Za-z0-9_]*[\"\047]?/)) {
        tok=substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", tok)
        gsub(/[\"\047]/, "", tok)
        pending=tok
      }
      print line
    }
  ' <<<"$1"
}
strip_cmd_quotes() { tr '\n' '\036' <<<"$1" | sed -E "s/'([^' <>|;&]*)'/\1/g; s/\"([^\" <>|;&]*)\"/\1/g; s/'[^']*'/__OVERSEER_ARG__/g; s/\"[^\"]*\"/__OVERSEER_ARG__/g" | tr '\036' '\n'; }
clean_cmd() { local c; c=$(strip_heredocs "$1"); strip_cmd_quotes "$c"; }

redir_targets() {
  local m
  while IFS= read -r m; do
    m=$(sed -E 's/^[^<>&]*&?>>?[[:space:]]*//' <<<"$m")
    [ -n "$m" ] && printf '%s\n' "$(strip_quotes "$m")"
  done < <(grep -oE '(^|[^<>=])>>?[[:space:]]*[^[:space:]<>|;&]+|(^|[^<>])&>>?[[:space:]]*[^[:space:]<>|;&]+' <<<"$1")
}
strip_redirect_words() {
  local a out="" skip=0
  local -a words
  local bare='^[0-9]*(>>?|<<?|>&|<&)$|^&>>?$'
  local attached='^[0-9]*(>>?|<<?|>&|<&)|^&>>?'
  read -r -a words <<<"$1"
  [ "${#words[@]}" -gt 0 ] || return
  for a in "${words[@]}"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    if [[ $a =~ $bare ]]; then skip=1; continue; fi
    if [[ $a =~ $attached ]]; then continue; fi
    out=${out:+$out }$a
  done
  printf '%s' "$out"
}
split_segments() {
  awk '{
    gsub(/\|\||&&|;|\|/, "\n")
    gsub(/(^|[ \t])&([ \t]|$)/, "\n")
    print
  }' <<<"$1"
}
strip_shell_prefix() {
  local seg=$1 w
  while :; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    case "$seg" in
      \(*|\{*) seg=${seg#?}; continue ;;
    esac
    case "$seg" in
      *')'|*'}') seg=${seg%?}; continue ;;
    esac
    w=${seg%%[[:space:]]*}
    case "$w" in
      '') break ;;
      [A-Za-z_]*=*) seg=${seg#"$w"} ;;
      then|do|else|elif|if|while|until|'!'|time|exec|xargs|sudo|command|builtin|env|nohup|nice) seg=${seg#"$w"} ;;
      timeout)
        seg=${seg#"$w"}
        while :; do
          seg=${seg#"${seg%%[![:space:]]*}"}
          w=${seg%%[[:space:]]*}
          seg=${seg#"$w"}
          case "$w" in -*) continue ;; *) break ;; esac
        done
        ;;
      *) break ;;
    esac
  done
  printf '%s' "$seg"
}
tee_targets() {
  local seg a
  while IFS= read -r seg; do
    local -a words
    read -r -a words <<<"$seg"
    [ "${#words[@]}" -gt 0 ] || continue
    for a in "${words[@]}"; do
      case "$a" in -*) ;; *) strip_quotes "$a"; echo ;; esac
    done
  done < <(grep -oE '(^|[;&|[:space:]])tee[[:space:]][^;&|]*' <<<"$1" | sed -E 's/^[;&|[:space:]]*tee[[:space:]]+//')
}
inplace_targets() {
  local seg
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    seg=$(strip_redirect_words "$seg")
    local -a w files
    read -r -a w <<<"$seg"
    [ "${#w[@]}" -gt 0 ] || continue
    local cmd=${w[0]} i=1 a have_script=0 inplace=0
    [ "$cmd" = sed ] || [ "$cmd" = perl ] || continue
    files=()
    while [ "$i" -lt "${#w[@]}" ]; do
      a=${w[$i]}
      case "$a" in
        -*)
          case "$a" in
            -i|--in-place|-i.*|--in-place=*) inplace=1 ;;
            -*) [[ $a =~ ^-[A-Za-z]*i ]] && inplace=1 ;;
          esac
          if [ "$cmd" = sed ]; then
            case "$a" in
              -e|--expression|-f|--file) have_script=1; i=$((i+1)) ;;
              --expression=*|--file=*) have_script=1 ;;
              -*) [[ $a =~ ^-[A-Za-z]*[eE]$ ]] && { have_script=1; i=$((i+1)); } ;;
            esac
          else
            case "$a" in
              -e|-E|-M|-I) have_script=1; i=$((i+1)) ;;
              -*) [[ $a =~ ^-[A-Za-z]*[eE]$ ]] && { have_script=1; i=$((i+1)); } ;;
            esac
          fi
          ;;
        *)
          if [ "$have_script" -eq 0 ]; then have_script=1
          else files+=("$a")
          fi
          ;;
      esac
      i=$((i+1))
    done
    if [ "$inplace" -eq 1 ] && [ "${#files[@]}" -gt 0 ]; then printf '%s\n' "${files[@]}"; fi
  done < <(split_segments "$1")
}
verb_segment() {
  local clean=$1 v
  for v in touch rm mkdir rmdir mv cp ln truncate; do
    local -a w args
    read -r -a w <<<"$clean"
    local i=0 start=-1 j target_dir=""
    if [ "${w[$i]:-}" = "$v" ]; then start=$((i+1))
    elif [ "${w[$i]:-}" = git ] && [ "${w[$((i+1))]:-}" = "$v" ]; then start=$((i+2))
    fi
    [ "$start" -ge 0 ] || continue
    args=()
    j=$start
    while [ "$j" -lt "${#w[@]}" ]; do
      case "${w[$j]}" in
        -t|--target-directory)
          j=$((j+1)); target_dir=$(strip_quotes "${w[$j]:-}")
          ;;
        --target-directory=*) target_dir=$(strip_quotes "${w[$j]#*=}") ;;
        -*) ;;
        *) args+=("$(strip_quotes "${w[$j]}")") ;;
      esac
      j=$((j+1))
    done
    case "$v" in
      cp)
        if [ -n "$target_dir" ]; then echo "$target_dir"
        elif [ "${#args[@]}" -gt 0 ]; then echo "${args[${#args[@]}-1]}"
        fi
        ;;
      mv)
        if [ -n "$target_dir" ]; then
          echo "$target_dir"
          [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
        else
          [ "${#args[@]}" -gt 0 ] && echo "${args[${#args[@]}-1]}"
          [ "${#args[@]}" -gt 1 ] && printf '%s\n' "${args[@]:0:${#args[@]}-1}"
        fi
        ;;
      *)
        [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
        ;;
    esac
  done
}
find_delete_segment() {
  local clean=$1
  local -a w
  read -r -a w <<<"$clean"
  [ "${#w[@]}" -gt 0 ] || return
  local i=0 k del=0
  [ "${w[$i]:-}" = find ] || return
  for ((k=i+1; k<${#w[@]}; k++)); do [ "${w[$k]}" = -delete ] && del=1; done
  [ "$del" -eq 1 ] || return
  k=$((i+1))
  while [ "$k" -lt "${#w[@]}" ]; do
    case "${w[$k]}" in
      -H|-L|-P) k=$((k+1)) ;;
      -D|-O) k=$((k+2)) ;;
      -*) break ;;
      *) strip_quotes "${w[$k]}"; echo; k=$((k+1)) ;;
    esac
  done
}
dd_segment() {
  local clean=$1
  local -a w
  read -r -a w <<<"$clean"
  [ "${#w[@]}" -gt 0 ] || return
  local i=0 k
  [ "${w[$i]:-}" = dd ] || return
  for ((k=i+1; k<${#w[@]}; k++)); do
    case "${w[$k]}" in of=*) strip_quotes "${w[$k]#of=}"; echo ;; esac
  done
}
write_targets() {
  local c; c=$(clean_cmd "$1")
  redir_targets "$c"
  tee_targets "$c"
  inplace_targets "$c"
}
guard_targets() {
  local seg clean
  write_targets "$1"
  while IFS= read -r seg; do
    seg=$(strip_shell_prefix "$seg")
    [ -n "$seg" ] || continue
    clean=$(strip_redirect_words "$seg")
    verb_segment "$clean"
    find_delete_segment "$clean"
    dd_segment "$clean"
  done < <(split_segments "$(clean_cmd "$1")")
}
revparse_overseer() {
  grep -Eq '(>>?[[:space:]]*["\047]?[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer|(^|[;&|[:space:]])(touch|rm|mkdir|rmdir|mv|cp|ln|truncate|tee|find|dd)[[:space:]][^;&|]*[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer|(^|[;&|[:space:]])(sed|perl)[[:space:]][^;&|]*(-[A-Za-z]*i|--in-place)[^;&|]*[$][(][[:space:]]*git rev-parse --git-(common-)?dir[^;&|]*/overseer)' <<<"$1"
}
cds_git() {
  local seg cdre="(^|[;&|[:space:]])(cd|pushd)[[:space:]][^;&|]*[\"']?[.]git([\"'[:space:]/]|$)"
  while IFS= read -r seg; do grep -Eq "$cdre" <<<"$seg" && return 0; done < <(tr ';|&' '\n' <<<"$1")
  return 1
}

stats() {
  local base=$1 counts esc deltas med files=() f
  echo "overseer stats ($base/overseer)"
  for f in "$base"/overseer/*.log "$base"/worktrees/*/overseer/*.log; do [ -f "$f" ] && files+=("$f"); done
  if [ "${#files[@]}" -eq 0 ]; then echo "blocks: none"; echo "escalations: 0"; echo "median unblock: -"; return 0; fi
  counts=$(awk '$2=="block"{n[$3]++} END{for (r in n) print r, n[r]}' "${files[@]}" | sort -k2,2nr -k1,1)
  esc=$(awk '$2=="escalate"{n++} END{print n+0}' "${files[@]}")
  deltas=$(awk '
    function mode(r) {
      if (r ~ /^post-edit-/) return "post-edit"
      if (r ~ /^edit-/) return "pre-edit"
      if (r ~ /^bash-/) return "pre-bash"
      if (r ~ /^(commit-|pr-)/) return "post-bash"
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

if [ "$mode" = stats ]; then
  up=$(git rev-parse --show-cdup 2>/dev/null) && cd "./$up" || { echo "overseer: stats must run inside a git repo" >&2; exit 1; }
  stats "$(abspath "$(git rev-parse --git-common-dir)")"
  exit 0
fi

input=$(cat)
workdir() {
  command -v jq >/dev/null || return
  local f d; f=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)
  [ "${f#/}" = "$f" ] && { jq -r '.cwd // empty' <<<"$input" 2>/dev/null; return; }
  d=${f%/*}; while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done; echo "${d:-/}"
}
wd=$(workdir)
{ [ -n "$wd" ] && cd "$wd" 2>/dev/null; } || cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
target_base=$(pwd)
up=$(git rev-parse --show-cdup 2>/dev/null) && cd "./$up" || exit 0
command -v jq >/dev/null || { echo "overseer: jq not found, rules are OFF" >&2; exit 1; }
[ -f "$(git rev-parse --git-common-dir)/overseer/off" ] && exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
dir="$(git rev-parse --git-dir)/overseer"
log="$dir/${branch//\//-}.log"
common=$(abspath "$(git rev-parse --git-common-dir)")
gitdir=$(abspath "$(git rev-parse --git-dir)")
ASK_PR_LINES=400 # ponytail: size only decides when to send a PR to split-pr-stack; the skill judges the cut
NO_SPEC='Spec impact: *None *(—|–|-|:) *[^ ]'
TESTS='\b(phpunit|pest|artisan test|pytest|vitest|jest|go test|cargo test|(npm|pnpm) (run )?test|yarn test|bun test|deno (task )?test|rspec|mix test|gradle test|mvn test)\b' # ponytail: fixed list; add a runner when a repo needs one
COMMIT='\bgit\b[^;&|]*\bcommit\b'
PR_CREATE='\bgh\s+pr\s+create\b'

matches() { jq -e --arg re "$1" '.tool_input.command // "" | test($re)' <<<"$input" >/dev/null; }
any() { local f; while read -r f; do "$@" "$f" && return 0; done; return 1; }
note() { mkdir -p "${log%/*}" && echo "$(date +%s) $1" >>"$log"; }
seen() { [ -f "$log" ] && awk "$1" "$log"; }
rule_mode() {
  case "$1" in
    post-edit-*) echo post-edit ;;
    edit-*) echo pre-edit ;;
    bash-*) echo pre-bash ;;
    commit-*|pr-*) echo post-bash ;;
  esac
}
streak() {
  [ -f "$log" ] || { echo 0; return; }
  local m; m=$(rule_mode "$1")
  awk -v m="$m" -v r="$1" '
    $2=="pass" { if ($3==m) n=0; next }
    $2=="block" { if ($3==r) n++; else n=0 }
    END { print n+0 }
  ' "$log"
}
block() {
  local rule=$1 n; shift
  n=$(streak "$rule"); n=$((n + 1))
  note "block $rule"
  if [ "$n" -ge 3 ]; then
    [ "$n" -eq 3 ] && note "escalate $rule"
    printf 'overseer: %s\noverseer: %s was blocked %s times in a row. Stop and ask the human before trying again.\n' "$*" "$rule" "$n" >&2
  else
    printf 'overseer: %s\n' "$*" >&2
  fi
  exit 2
}
outstanding() {
  [ -f "$log" ] || return 1
  awk -v m="$1" '
    function mode(r) {
      if (r ~ /^post-edit-/) return "post-edit"
      if (r ~ /^edit-/) return "pre-edit"
      if (r ~ /^bash-/) return "pre-bash"
      if (r ~ /^(commit-|pr-)/) return "post-bash"
      return ""
    }
    $2=="block" && mode($3)==m { p=1 }
    $2=="pass" && $3==m { p=0 }
    END { exit !p }
  ' "$log"
}
ok() { outstanding "$mode" && note "pass $mode"; exit 0; }

is_code() { case "$1" in *.php|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.py|*.go|*.rs|*.rb|*.java|*.kt|*.swift|*.c|*.cc|*.cpp|*.h|*.cs|*.vue|*.svelte) return 0 ;; esac; return 1; }
is_spec() { case "$1" in specs/*|openspec/*) return 0 ;; esac; return 1; }
is_test() { case "/$1" in */tests/*|*/test/*|*/__tests__/*|*/spec/*|*Test.*|*_test.*|*.test.*|*.spec.*|*/test_*.py) return 0 ;; esac; return 1; }
is_commented() { is_code "$1" || case "$1" in *.yaml|*.yml|*.toml|*.sh|*.bash|*Dockerfile|*Makefile) true ;; *) false ;; esac; }
is_code_test() { is_code "$1" && is_test "$1"; }
is_prod() { is_code "$1" && ! is_test "$1" && ! is_spec "$1"; }
is_overseer_target() {
  local a
  [ -n "$1" ] || return 1
  case "$1" in .git/overseer|.git/overseer/*|*/.git/overseer|*/.git/overseer/*|.git/worktrees/*/overseer*|*/.git/worktrees/*/overseer*) return 0 ;; esac
  a=$(abspath_from "$target_base" "$1")
  case "$a" in "$common/overseer"|"$common/overseer/"*|"$gitdir/overseer"|"$gitdir/overseer/"*) return 0 ;; esac
  return 1
}
is_git_dir_target() {
  local a
  [ -n "$1" ] || return 1
  case "$1" in .git|.git/|*/.git|*/.git/) return 0 ;; esac
  a=$(abspath_from "$target_base" "$1")
  [ "$a" = "$common" ] || [ "$a" = "$gitdir" ] && return 0
  return 1
}
rel_target() {
  local a; a=$(abspath_from "$target_base" "$1")
  case "$a" in "$PWD"/*) printf '%s' "${a#"$PWD"/}" ;; esac
}

default_base() {
  git symbolic-ref -q --short refs/remotes/origin/HEAD && return
  local b; for b in origin/main origin/master main master; do git rev-parse -q --verify "$b" >/dev/null && { echo "$b"; return; }; done
}
branch_files() {
  local b; b=$(default_base)
  [ -n "$b" ] && git diff --name-only "$b"...HEAD 2>/dev/null
  dirty_files
}
has_spec() {
  branch_files | grep -Eq '^(specs/[^/]+/spec\.md|openspec/changes/[^/]+/)' && return
  local b; b=$(default_base)
  [ -n "$b" ] && git log --format=%B "$b"..HEAD 2>/dev/null | grep -Eq "$NO_SPEC"
}
inherit() {
  [ -f "$log" ] || [ "$branch" = HEAD ] || [ ! -d "$dir" ] && return
  local b n best='' min=''
  while read -r b; do
    [ "$b" != "$branch" ] && [ -f "$dir/${b//\//-}.log" ] && git merge-base --is-ancestor "$b" HEAD 2>/dev/null || continue
    n=$(git rev-list --count "$b"..HEAD)
    [ -z "$min" ] || [ "$n" -lt "$min" ] && { min=$n; best=$b; }
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)
  [ -z "$best" ] || awk '$2!="block" && $2!="escalate" && $2!="pass"' "$dir/${best//\//-}.log" >"$log"
}

rel_file() {
  local f; f=$(jq -r '.tool_input.file_path // empty' <<<"$input")
  case "$f" in "$PWD"/*) echo "${f#"$PWD"/}" ;; /*) ;; *) echo "$f" ;; esac
}
added_lines() {
  if git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    git diff -U0 HEAD -- "$1" | awk '/^@@/{split($3,a,","); n=substr(a[1],2)+0; next} /^\+\+\+/{next} /^\+/{print n ":" substr($0,2); n++}'
  else
    grep -n '' -- "$1"
  fi
}
prose_comments() {
  added_lines "$1" |
    grep -E '^[0-9]+:[[:space:]]*(//|#|/\*|\*|\{\{--|<!--)' |
    grep -vE '^[0-9]+:[[:space:]]*(#!|#\[|(//|#|/\*+|\*/?|\{\{--|<!--|-->|--\}\})[[:space:]]*$)' |
    grep -vE '@[A-Za-z]|phpcs:|phpstan-|psalm-|eslint-|prettier-ignore|@ts-|noqa|type: ?ignore|pylint:|nolint|NOSONAR|//go:|(end)?region|istanbul|c8 ignore|-\*-|shellcheck|yamllint|ponytail:'
}
prod_gate() {
  local f=$1 spec_rule=$2 red_rule=$3
  has_spec || block "$spec_rule" "no spec in this branch. Write specs/NNN-<slug>/spec.md (or an openspec/changes/<name>/ proposal) before touching $f."
  seen '$2=="test-edit"{t=1} t&&$2=="red"{r=1} END{exit !r}' || # ponytail: once per branch, not per cycle; refactoring on green is legitimate
    block "$red_rule" "red first. Write or change a test for this behaviour, run it and watch it fail, then touch $f."
}
write_gate() {
  local c=$1 ts t f
  revparse_overseer "$(strip_heredocs "$c")" && block bash-overseer "do not write to the overseer state directory (resolved through git rev-parse). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  ts=$(guard_targets "$c")
  [ -n "$ts" ] && cds_git "$(clean_cmd "$c")" && block bash-overseer "do not change into .git and then write to the overseer state directory. The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    is_overseer_target "$t" && block bash-overseer "do not write to the overseer state directory ($t). The escape hatch belongs to the human: create or remove .git/overseer/off from your own terminal."
    is_git_dir_target "$t" && block bash-git-dir "do not write to, remove or move the git directory itself ($t). It holds the branch, the history and the overseer state; change it only through git commands."
  done <<<"$ts"
  ts=$(write_targets "$c")
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    f=$(rel_target "$t")
    is_prod "$f" && prod_gate "$f" bash-spec bash-red
  done <<<"$ts"
}
cmd() { jq -r '.tool_input.command // ""' <<<"$input"; }
dirty_files() { git status --porcelain --untracked-files=all | cut -c4-; }

inherit
case "$mode" in
  session)
    cat "${0%/*}/../rules/overseer.md"
    ;;
  pre-edit)
    f=$(rel_file); [ -n "$f" ] && is_prod "$f" || ok
    prod_gate "$f" edit-spec edit-red
    ;;
  post-edit)
    f=$(rel_file); [ -n "$f" ] || ok
    if is_prod "$f"; then note prod-edit; elif is_code_test "$f"; then note test-edit; fi
    [ -f "$f" ] && is_commented "$f" || ok
    p=$(prose_comments "$f" | head -n 10)
    [ -z "$p" ] || { note "prose $f"; block post-edit-prose "$(printf 'prose comments added to %s. Delete them; the why of a change goes in the PR as a review comment on that line:\n%s' "$f" "$p")"; }
    ;;
  pre-bash)
    c=$(cmd)
    write_gate "$c"
    if matches "$COMMIT"; then
      dirty_files | any is_code || ok
      matches "$TESTS" && block bash-tests-own "run the tests in their own command, then commit in another; overseer only trusts a run it has seen finish."
      seen '$2~/^(test-edit|prod-edit|red|green)$/{l=$2} END{exit l!="green"}' ||
        block bash-green "the last thing that happened was not a green test run. Run the tests, get them green, then commit."
    fi
    if matches "$PR_CREATE"; then
      b=$(grep -oE -- '(--base|-B)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--base|-B)[ =]+//')
      if [ -n "$b" ]; then git rev-parse -q --verify "origin/$b" >/dev/null && b="origin/$b"; else b=$(default_base); fi
      h=$(grep -oE -- '(--head|-H)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--head|-H)[ =]+//')
      [ -n "$h" ] || h=HEAD
      n=0
      [ "$b" = "$(default_base)" ] && while IFS=$'\t' read -r a d f; do is_prod "$f" && [ "$a" != - ] && n=$((n + a + d)); done < <(git diff --numstat "$b...$h" 2>/dev/null)
      body=$c; bf=$(grep -oE -- '(--body-file|-F)[ =]+[^ ]+' <<<"$c" | head -1 | sed -E 's/^(--body-file|-F)[ =]+//')
      [ -n "$bf" ] && [ -f "$bf" ] && body+=$(cat "$bf")
      [ "$n" -le "$ASK_PR_LINES" ] || grep -q 'Why not smaller:' <<<"$body" ||
        block bash-pr-size "this PR changes $n lines of production code vs $b. Cut it into a stack by function with the split-pr-stack skill (caravan): each PR builds, passes its tests and can be reviewed on its own. If it cannot be smaller, say why in the body: 'Why not smaller: ...'."
      grep -Eq "specs/|openspec/changes/|$NO_SPEC" <<<"$body" || block bash-pr-spec "the PR body must link its spec (the specs/... or openspec/changes/... path), or say 'Spec impact: None — <why>'."
    fi
    ;;
  post-bash | bash-failed)
    matches "$TESTS" && { [ "$mode" = post-bash ] && note green || note red; } # ponytail: any failure is red, even command-not-found; tighten if a fake red ever slips through
    if [ "$mode" = post-bash ] && matches "$PR_CREATE" && [ -f "$log" ]; then
      w=$(awk '$2=="prose"{print $3}' "$log" | sort -u | tr '\n' ' ')
      [ -z "$w" ] || block pr-comments "PR open. Earlier you had to delete prose comments from: $w. Post the why of those changes as review comments on their lines (gh api repos/{owner}/{repo}/pulls/<number>/comments with path, line, side=RIGHT, commit_id)."
    fi
    if [ "$mode" = post-bash ] && matches "$COMMIT"; then
      files=$(git show --name-only --format= HEAD 2>/dev/null)
      any is_prod <<<"$files" && ! any is_code_test <<<"$files" &&
        block commit-test "that commit changes production code but no test. Fine for a pure refactor; otherwise add the test that pins the behaviour."
    fi
    ;;
  *)
    echo "usage: overseer.sh session|pre-edit|post-edit|pre-bash|post-bash|bash-failed|stats  (hook JSON on stdin)" >&2
    exit 1
    ;;
esac
ok
