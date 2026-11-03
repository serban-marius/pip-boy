BEGIN {
  COMMENT = "^[[:space:]]*(//|#|/\\*|\\*|\\{\\{--|<!--)"
  STRUCTURAL = "^[[:space:]]*(#!|#\\[)"
  STAR = "^[[:space:]]*\\*+[A-Za-z_$(&]"
  DOC_WORD = "^[[:space:]]*\\*+[A-Za-z][A-Za-z0-9_$]*[[:space:]]*:?[[:space:]]+[A-Za-z]"
  ID = "[A-Za-z_$][A-Za-z0-9_$]*"
  DIRECTIVE = "^(phpcs:|phpstan-|psalm-|eslint-|prettier-ignore|@ts-|noqa|type: ?ignore|pylint:|flake8:|nolint|NOSONAR|go:|#?(end)?region([[:space:]:]|$)|istanbul[[:space:]]+ignore[[:space:]]+(if|else|next|file)|c8 ignore|-\\*-|shellcheck|yamllint|ponytail:|\\{@inheritDoc\\}|deno-(lint|fmt)-ignore|biome-ignore|fmt: ?(off|on|skip)|isort:|mypy:|pyright:|ruff:|rubocop:|jshint[[:space:]]+(-W[0-9]+|[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*:)|globals?[[:space:]]+" ID "(:[[:space:]]*[A-Za-z]+)?([[:space:]]*,[[:space:]]*" ID "(:[[:space:]]*[A-Za-z]+)?)*$|<reference |<amd-module|(syntax|escape|check)=[^[:space:]]+$|yaml-language-server:|cspell:|webpackChunkName|@vite-ignore|@jsx(Runtime|ImportSource|Frag)?([[:space:]]+[^[:space:]]+)?$|@(no)?flow([[:space:]]+strict(-local)?)?$)"
  TYPED = "^(param|return|returns|var|throws|extends|implements|mixin|type|template(-(co|contra)variant|-extends|-implements|-use)?|typedef|property|property-read|property-write|(phpstan|psalm)-(param|return|var|extends|implements|property|property-read|property-write|assert|assert-if-true|assert-if-false|self-out|this-out))$"
  NAMED = "^(param|var|property|property-read|property-write|typedef|(phpstan|psalm)-(param|var|property|property-read|property-write|assert|assert-if-true|assert-if-false))$"
  WHOLE = "^(phpstan-|psalm-|(dataProvider|covers|uses|group|test|depends|dependsUsingDeepClone|dependsUsingShallowClone|dependsExternal|dependsExternalUsingDeepClone|dependsExternalUsingShallowClone|before|after|beforeClass|afterClass|coversDefaultClass|coversNothing|usesDefaultClass|testdox|codeCoverageIgnoreStart|codeCoverageIgnoreEnd|runInSeparateProcess|runTestsInSeparateProcesses|preserveGlobalState|requires|testWith|codeCoverageIgnore|inheritDoc|jest-environment|jest-environment-options|vitest-environment|jsx|flow|deno-types)$)"
}

{
  text = $0
  sub(/^[0-9]+:/, "", text)
  if (text ~ COMMENT && text !~ STRUCTURAL && !(text ~ STAR && text !~ DOC_WORD) && is_prose(comment_body(text))) print
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
  if (tag == "method") return rest !~ /\)[[:space:]]*$/
  if (tag ~ WHOLE) return 0
  return rest != ""
}

function has_trailing_prose(tag, rest) {
  rest = after_type(rest)
  if (tag ~ /^template(-(co|contra)variant)?$/ && rest ~ /^(of|as)[[:space:]]/) {
    sub(/^(of|as)[[:space:]]+/, "", rest)
    rest = after_type(rest)
  }
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
