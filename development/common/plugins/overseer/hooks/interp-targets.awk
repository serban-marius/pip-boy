BEGIN { src = ""; BAD = "\001" }
{ src = src $0 "\n" }
function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}
function literal(s,   t, q, inner) {
  t = trim(s)
  if (match(t, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) t = trim(substr(t, RLENGTH + 1))
  q = substr(t, 1, 1)
  if (length(t) < 2 || (q != "\"" && q != "'")) return BAD
  if (substr(t, length(t), 1) != q) return BAD
  inner = substr(t, 2, length(t) - 2)
  if (inner ~ /["']/) return BAD
  return inner
}
function receiver(pre,   t, rec, l, r) {
  t = trim(pre)
  sub(/[ \t\r\n]*\.[ \t\r\n]*$/, "", t)
  if (!match(t, /[A-Za-z_][A-Za-z0-9_.]*[ \t]*\([^()]*\)[ \t]*$/)) return BAD
  rec = substr(t, RSTART, RLENGTH)
  l = index(rec, "(")
  r = length(rec)
  while (r > l && substr(rec, r, 1) != ")") r--
  if (r <= l) return BAD
  return literal(substr(rec, l + 1, r - l - 1))
}
function emit(path, name) {
  if (path == BAD) print "?" name
  else if (path != "") print path
}
function fs_receiver(pre,   t) {
  t = trim(pre)
  if (t ~ /(^|[^A-Za-z0-9_])fs(p)?(\.[A-Za-z0-9_]+)*$/) return 1
  if (t ~ /require\("fs"\)$/ || t ~ /require\('fs'\)$/) return 1
  return 0
}
END {
  gsub(/\\"/, "\"", src)
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
    if (!closed) {
      if (name ~ /^(writeFileSync|appendFileSync|createWriteStream|file_put_contents|write_bytes|write_text|FileUtils\.cp|FileUtils\.mv|shutil\.(copy|move|copyfile|copy2|copytree)|os\.(rename|replace)|copyFile|appendFile|writeFile|File\.write|IO\.write)$/) print "?" name
      pos = after
      continue
    }
    prev = (at > 1) ? substr(src, at - 1, 1) : ""
    if (name == "copy" || name == "rename") {
      if (prev == ".") {
        pre = substr(src, 1, at - 1)
        sub(/[ \t\r\n]*\.[ \t\r\n]*$/, "", pre)
        if (!fs_receiver(pre)) { pos = after; continue }
      }
      if (nargs < 2) { pos = after; continue }
    }
    if (name == "open" && prev == ".") {
      pre = substr(src, 1, at - 1)
      sub(/[ \t\r\n]*\.[ \t\r\n]*$/, "", pre)
      if (pre !~ /File$/) { pos = after; continue }
    }
    if (name == "open" || name == "File.open" || name == "fopen") {
      mode = literal(args[2])
      if (mode == BAD) { pos = after; continue }
      if (name == "open" && nargs >= 3 && (mode == ">" || mode == ">>" || mode == "+<" || mode == "+>")) {
        emit(literal(args[3]), name)
        pos = after
        continue
      }
      if (name == "open" && mode ~ /^(>>|>|\+<|\+>)/) {
        path = mode
        if (substr(path, 1, 2) == ">>" || substr(path, 1, 2) == "+<" || substr(path, 1, 2) == "+>") path = substr(path, 3)
        else path = substr(path, 2)
        path = trim(path)
        if (path != "") emit(path, name)
        pos = after
        continue
      }
      if (mode !~ /^[rwaxbtcU+]+$/ || mode !~ /[waxc+]/) { pos = after; continue }
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
