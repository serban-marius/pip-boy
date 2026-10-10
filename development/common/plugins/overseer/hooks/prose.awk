BEGIN {
  COMMENT = "^[[:space:]]*(//|#|/\\*|\\*|\\{\\{--|<!--)"
  STRUCTURAL = "^[[:space:]]*(#!|#\\[)"
  DIRECTIVE = "^(phpcs:|phpstan-|psalm-|eslint-|prettier-ignore|@ts-|noqa|type: ?ignore|pylint:|nolint|NOSONAR|go:|#?(end)?region|istanbul|c8 ignore|-\\*-|shellcheck|yamllint|ponytail:|\\{@inheritDoc\\})"
  TYPED = "^(param|return|returns|var|throws|extends|implements|mixin|type|typedef|property|property-read|property-write|(phpstan|psalm)-(param|return|var|extends|implements|property|property-read|property-write|assert|assert-if-true|assert-if-false|self-out|this-out))$"
  NAMED = "^(param|var|property|property-read|property-write|typedef|(phpstan|psalm)-(param|var|property|property-read|property-write|assert|assert-if-true|assert-if-false))$"
  WHOLE = "^(phpstan-|psalm-|ts-|template|method|dataProvider|covers|uses|group|test|depends|before|after|runInSeparateProcess|runTestsInSeparateProcesses|preserveGlobalState|requires|testWith|codeCoverageIgnore|inheritDoc|jest-environment|vitest-environment|jsx|flow)"
}

{
  text = $0
  sub(/^[0-9]+:/, "", text)
  if (text ~ COMMENT && text !~ STRUCTURAL && is_prose(comment_body(text))) print
}

function comment_body(s) {
  sub(/^[[:space:]]*(\/\*+|\*+\/?|\/\/+|#+|\{\{--|<!--)[[:space:]]*/, "", s)
  sub(/[[:space:]]*(\*\/|-->|--\}\})[[:space:]]*$/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function is_prose(body,   tag, rest) {
  if (body == "" || body ~ /^[-*\/]+$/ || body ~ DIRECTIVE) return 0
  if (body !~ /^@[A-Za-z]/) return 1
  tag = body; sub(/^@/, "", tag); sub(/[[:space:]].*$/, "", tag)
  rest = substr(body, length(tag) + 2); sub(/^[[:space:]]+/, "", rest)
  if (tag ~ TYPED) return has_trailing_prose(tag, rest)
  if (tag ~ WHOLE) return 0
  return rest != ""
}

function has_trailing_prose(tag, rest) {
  rest = after_type(rest)
  if (tag ~ NAMED) rest = after_name(rest)
  return rest != ""
}

function after_type(s,   i, c, depth) {
  depth = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c ~ /[<{(\[]/) depth++
    else if (c ~ /[>})\]]/ && !(c == ">" && substr(s, i - 1, 1) == "-")) depth--
    else if (c ~ /[[:space:]]/ && depth <= 0 && substr(s, i - 1, 1) !~ /[:,|&]/ && substr(s, i + 1, 1) !~ /[|&]/) break
  }
  s = substr(s, i); sub(/^[[:space:]]+/, "", s)
  return s
}

function after_name(s) {
  sub(/^&?(\.\.\.)?&?\$?[A-Za-z_][A-Za-z0-9_.]*/, "", s) || sub(/^\[[^\]]*\]/, "", s)
  sub(/^[[:space:]]+/, "", s)
  return s
}
