BEGIN {
  MAX_BODY = 15; MAX_NEST = 2; MAX_PARAMS = 4; MAX_FILE = 200
  WORD = "[A-Za-z_$][A-Za-z0-9_$]*"
  NESTS = "(^|[^A-Za-z0-9_$])(if|else|elseif|for|foreach|while|do|switch|try|catch|finally|match|select|loop|when|unless|guard|function|fn|func|fun)([^A-Za-z0-9_$]|$)|=>"
  STATEMENT = "^[[:space:]]*(if|else|elseif|for|foreach|while|do|switch|try|catch|finally|match|select|loop|when|unless|guard|with)([^A-Za-z0-9_$]|$)"
  TYPE_DECL = "(^|[^A-Za-z0-9_$])(class|interface|trait|enum|struct|impl|namespace|record|object|module|extension|protocol|union)([^A-Za-z0-9_$]|$)"
  PY_NESTS = "^[[:space:]]*(if|elif|else|for|while|with|try|except|finally|match|def|async[[:space:]]+(for|with|def))([^A-Za-z0-9_]|$).*:[[:space:]]*$"
  CONSTRUCTOR = "^(__construct|constructor|__init__|init|new)$"
  split(changed, list, " "); for (k in list) touched[list[k]] = 1
}

FNR == 1 { python = FILENAME ~ /\.py$/; php = FILENAME ~ /\.php$/ }
python { python_line($0); next }
{ brace_line($0) }

END {
  if (python && in_fn) end_python_fn()
  if (lines > MAX_FILE) print "file: " lines " lines (max " MAX_FILE ")"
}

function brace_line(raw,   code, i, c) {
  code = code_of(raw)
  if (code ~ /[^[:space:]]/) count_line(code)
  for (i = 1; i <= length(code); i++) {
    c = substr(code, i, 1)
    if (c == "{") open_brace()
    else if (c == "}") close_brace()
    else if (c == ";") reset_head()
    else extend_head(c)
  }
  end_head_line()
}

function code_of(s,   i) {
  if (in_comment) { i = index(s, "*/"); if (!i) return ""; s = substr(s, i + 2); in_comment = 0 }
  gsub(/"([^"\\]|\\.)*"/, "\"\"", s); gsub(/'([^'\\]|\\.)*'/, "''", s); gsub(/`([^`\\]|\\.)*`/, "``", s)
  gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, " ", s)
  sub(/\/\/.*$/, "", s)
  if (php) sub(/#([^[].*)?$/, "", s)
  if (i = index(s, "/*")) { s = substr(s, 1, i - 1); in_comment = 1 }
  return s
}

function count_line(code) {
  lines++
  if (in_fn && code !~ /^[[:space:]]*[]});,]+[[:space:]]*$/) body++
}

function extend_head(c) {
  if (head == "" && c ~ /[[:space:]]/) return
  if (head == "") head_line = FNR
  head = head c
}

function reset_head() { head = ""; statement_at = 0 }

function end_head_line(   open) {
  if (head == "") return
  open = gsub(/\(/, "(", head) - gsub(/\)/, ")", head)
  if (open == 0 && head ~ /[A-Za-z0-9_$)\]"'`][[:space:]]*$/) { statement_at = length(head); statement_line = FNR + 1 }
  extend_head("\n")
}

function open_brace(   h, line) {
  if (is_literal(head)) { literals[++ks] = 1; saved[ks] = head; saved_at[ks] = statement_at; head = ""; return }
  literals[++ks] = 0
  h = current_statement(); line = h == head ? head_line : statement_line
  if (in_fn) push_block(h ~ NESTS)
  else if (is_function_head(h)) start_fn(h, line)
  else remember_class(h)
  depth++; reset_head()
}

function close_brace() {
  if (ks > 0 && literals[ks]) { head = saved[ks] "{}"; statement_at = saved_at[ks--]; return }
  if (ks > 0) ks--
  depth--; reset_head()
  if (!in_fn) return
  if (depth == fn_depth) { end_fn(FNR); return }
  nest -= blocks[sp--]
}

function is_literal(h) {
  sub(/[[:space:]]+$/, "", h)
  return h ~ /[(,:=[?|&!<+-]$/ || h ~ /(^|[^A-Za-z0-9_$])(return|yield|await|default|case|in|of)$/
}

function current_statement(   rest) {
  rest = substr(head, statement_at + 1)
  return statement_at && rest ~ /[^[:space:]]/ && (rest ~ /\(.*\)/ || rest ~ /=>/ || rest ~ STATEMENT) ? rest : head
}

function push_block(nests) {
  blocks[++sp] = nests; nest += nests
  if (nest > max_nest) max_nest = nest
}

function is_function_head(h,   before) {
  if (h !~ /\(.*\)/ && h !~ /=>/) return 0
  before = index(h, "(") ? substr(h, 1, index(h, "(") - 1) : h
  return before !~ TYPE_DECL && h !~ STATEMENT && final_line_of(h) !~ STATEMENT
}

function final_line_of(h) { sub(/[[:space:]]+$/, "", h); return match(h, /\n[^\n]*$/) ? substr(h, RSTART + 1) : h }

function remember_class(h) {
  if (match(h, "(class|struct|record)[[:space:]]+" WORD)) class_name = last_word(substr(h, RSTART, RLENGTH))
}

function start_fn(h, line) {
  in_fn = 1; fn_depth = depth; fn_line = line; body = 0; nest = 0; max_nest = 0; sp = 0
  fn_name = name_of(h); fn_params = param_count(h, name_end)
}

function end_fn(line) {
  in_fn = 0
  if (was_touched(fn_line, line)) report()
}

function was_touched(from, to,   i) {
  for (i = from; i <= to; i++) if (i in touched) return 1
  return 0
}

function report(   issues) {
  if (body > MAX_BODY) issues = issues ", " body " body lines (max " MAX_BODY ")"
  if (max_nest > MAX_NEST) issues = issues ", nesting " max_nest " (max " MAX_NEST ")"
  if (fn_params > MAX_PARAMS && !is_constructor()) issues = issues ", " fn_params " parameters (max " MAX_PARAMS ")"
  if (issues != "") print fn_line ": " fn_name ": " substr(issues, 3)
}

function is_constructor() { return fn_name ~ CONSTRUCTOR || fn_name == class_name }

function name_of(h,   s) {
  if (match(h, "function[[:space:]]*&?[[:space:]]*" WORD) || match(h, "(fn|func|fun|def)[[:space:]]+(\\([^)]*\\)[[:space:]]*)?" WORD)) {
    name_end = RSTART + RLENGTH; return last_word(substr(h, RSTART, RLENGTH))
  }
  if (match(h, "(const|let|var)[[:space:]]+" WORD)) { name_end = RSTART + RLENGTH; return last_word(substr(h, RSTART, RLENGTH)) }
  name_end = 1
  s = index(h, "(") ? substr(h, 1, index(h, "(") - 1) : h
  sub(/[[:space:]]*(=|:)?[[:space:]]*(async)?[[:space:]]*(function)?[[:space:]]*(<[^>]*>)?[[:space:]]*$/, "", s)
  return last_word(s)
}

function last_word(s) {
  if (!match(s, WORD "[[:space:]]*$")) return "anonymous"
  s = substr(s, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", s)
  return s ~ /^(return|export|default|async|await|new|yield)$/ ? "anonymous" : s
}

function param_count(h, from,   i, c, d, n, part) {
  i = index(substr(h, from), "("); if (!i) return 0
  for (i += from - 1; i <= length(h); i++) {
    c = substr(h, i, 1)
    if (c ~ /[(<\[{]/ && d++ == 0) continue
    if (c ~ /[)>\]}]/ && !(c == ">" && substr(h, i - 1, 1) ~ /[-=]/) && --d == 0) break
    if (d == 1 && c == ",") { n += is_param(part); part = ""; continue }
    part = part c
  }
  return n + is_param(part)
}

function is_param(part) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", part)
  return part ~ /[A-Za-z0-9_$]/ && part !~ /^(self|cls|&self|&mut self|mut self)$/
}

function python_line(raw,   code, indent) {
  code = raw; sub(/#.*$/, "", code)
  if (code !~ /[^[:space:]]/) return
  lines++
  match(raw, /^[[:space:]]*/); indent = RLENGTH
  if (in_fn && !in_signature && indent <= fn_indent) end_python_fn()
  if (in_signature) continue_signature(code)
  else if (in_fn) python_body(code, indent)
  else if (code ~ /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]/) start_python_fn(code, indent)
  else remember_class(code)
  last_line = FNR
}

function start_python_fn(code, indent) {
  in_fn = 1; fn_indent = indent; fn_line = FNR; body = 0; nest = 0; max_nest = 0; sp = 0
  head = ""; in_signature = 1; continue_signature(code)
}

function continue_signature(code,   opened) {
  head = head " " code
  opened = gsub(/\(/, "(", head) - gsub(/\)/, ")", head)
  if (opened > 0 || code !~ /:[[:space:]]*$/) return
  in_signature = 0; fn_name = name_of(head); fn_params = param_count(head, name_end)
}

function python_body(code, indent) {
  body++
  while (sp > 0 && indents[sp] >= indent) sp--
  if (code ~ PY_NESTS) indents[++sp] = indent
  if (sp > max_nest) max_nest = sp
}

function end_python_fn() {
  in_fn = 0
  if (was_touched(fn_line, last_line)) report()
}
