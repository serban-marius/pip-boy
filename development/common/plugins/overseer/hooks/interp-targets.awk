BEGIN { src = ""; BAD = "\001" }
{ src = src $0 "\n" }
function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}
function literal(s,   t, q) {
  t = trim(s)
  if (match(t, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) t = trim(substr(t, RLENGTH + 1))
  q = substr(t, 1, 1)
  if (length(t) < 2 || (q != "\"" && q != "'")) return BAD
  if (substr(t, length(t), 1) != q) return BAD
  return substr(t, 2, length(t) - 2)
}
function receiver(pre,   t, rec) {
  sub(/[ \t\r\n]*\.[ \t\r\n]*$/, "", pre)
  if (!match(pre, /[A-Za-z_][A-Za-z0-9_.]*[ \t]*\([^()]*\)[ \t]*$/)) return BAD
  rec = substr(pre, RSTART, RLENGTH)
  if (!match(rec, /["'][^"']*["']/)) return BAD
  return literal(substr(rec, RSTART, RLENGTH))
}
function emit(path, name) {
  if (path == BAD) print "?" name
  else if (path != "") print path
}
END {
  names = "writeFileSync|appendFileSync|createWriteStream|file_put_contents|write_bytes|write_text|FileUtils\\.cp|FileUtils\\.mv|shutil\\.copytree|shutil\\.copyfile|shutil\\.copy2|shutil\\.copy|shutil\\.move|os\\.rename|os\\.replace|copyFile|appendFile|writeFile|File\\.write|File\\.open|IO\\.write|fopen|copy|rename|open"
  pos = 1
  while (pos <= length(src)) {
    rem = substr(src, pos)
    if (!match(rem, names)) break
    name = substr(rem, RSTART, RLENGTH)
    at = pos + RSTART - 1
    after = at + RLENGTH
    if (at > 1 && substr(src, at - 1, 1) ~ /[A-Za-z0-9_]/) { pos = after; continue }
    j = after
    while (j <= length(src) && substr(src, j, 1) ~ /[ \t\r\n]/) j++
    if (substr(src, j, 1) != "(") { pos = after; continue }
    nargs = 0
    delete args
    i = j + 1
    depth = 0
    q = ""
    cur = ""
    closed = 0
    while (i <= length(src)) {
      ch = substr(src, i, 1)
      if (q != "") {
        cur = cur ch
        if (ch == "\\") {
          if (i < length(src)) { cur = cur substr(src, i + 1, 1); i++ }
        } else if (ch == q) q = ""
      } else if (ch == "\"" || ch == "'" || ch == "`") {
        q = ch
        cur = cur ch
      } else if (ch == "(" || ch == "[" || ch == "{") {
        depth++
        cur = cur ch
      } else if (ch == ")" && depth == 0) {
        nargs++
        args[nargs] = cur
        closed = 1
        break
      } else if (ch == ")" || ch == "]" || ch == "}") {
        depth--
        cur = cur ch
      } else if (ch == "," && depth == 0) {
        nargs++
        args[nargs] = cur
        cur = ""
      } else cur = cur ch
      i++
    }
    if (!closed) { pos = after; continue }
    if (name == "open" || name == "File.open" || name == "fopen") {
      mode = literal(args[2])
      if (mode == BAD) { pos = after; continue }
      if (mode !~ /[waxc+]/) { pos = after; continue }
      emit(literal(args[1]), name)
    } else if (name == "write_text" || name == "write_bytes") {
      emit(receiver(substr(src, 1, at - 1)), name)
    } else if (name == "shutil.copytree" || name == "shutil.copyfile" || name == "shutil.copy2" || name == "shutil.copy" || name == "shutil.move" || name == "os.rename" || name == "os.replace" || name == "copy" || name == "rename" || name == "copyFile" || name == "FileUtils.cp" || name == "FileUtils.mv") {
      emit(literal(args[2]), name)
    } else {
      emit(literal(args[1]), name)
    }
    pos = after
  }
}
