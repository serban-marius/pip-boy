#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass

DEFAULT_IMAGE = "cloudutil/mcp-atlassian:latest"
CONVERT_CODE = (
    "import sys; from mcp_atlassian.preprocessing.jira import JiraPreprocessor as P; "
    "sys.stdout.write(P().markdown_to_jira(sys.stdin.read()))"
)


@dataclass(frozen=True)
class Warning:
    line: int
    severity: str
    code: str
    message: str


class ConversionError(Exception):
    pass


ERRORS = {
    "star-bullet-bold": "'* ' bullet with bold on the line comes out garbled -> start the bullet with '- '",
    "indented-bullet": "indented bullet renders flat -> write '*- child' at the start of the line",
    "nested-bold": "bold on a '*-' / '*#' line comes out garbled -> drop the bold on nested lines",
    "indented-number": "indented '1.' renders an empty item -> write '1.' at the start of the line",
    "hash-no-space": "a line starting with '#' becomes an h1 heading -> reword so it does not start with '#'",
    "rule-line": "a line of only -, *, _ or = turns the line above into a heading -> for a horizontal rule write '---- ' (four dashes and a trailing space)",
    "angle-brackets": "every <x> becomes [x], in code too -> use words, a bare URL or [text](url)",
    "dunder": "__word__ becomes bold, in code too -> link to the code instead",
    "stray-stars": "single * characters pair up and become _ -> reword, or one per line",
    "md-quote": "'> ' stays a literal '>' -> use {quote} ... {quote}",
    "md-image": "![alt](url) embeds an external image -> use a link",
    "bad-link": "this link breaks: '(' or '__' in the URL, a title, or ']' in the text -> simplify the link",
    "table-align": "alignment colons stop the table from converting -> separator of dashes only",
    "table-no-pipes": "a table without outer pipes is not converted -> put | at both ends of every row",
    "bad-fence": "this fence is not recognised (language not a single word, ~~~, or CRLF) -> ```lang with LF line endings",
    "fence-content": "inside a code block this line is rewritten like prose (list, heading or table) -> link the code instead",
    "task-box": "'[ ]' task boxes stay literal brackets -> plain bullets",
    "double-question": "'??' makes the MCP spin forever after posting (its reply converter backtracks), and every later Jira call hangs -> never write '??', even in code",
}

NOTES = {
    "icon": "renders as an icon -> fine if you meant one, otherwise reword",
    "underline": "+word+ renders underlined",
    "at-mention": "@name is not a mention -> plain name, or [~accountid:ID] to notify",
    "shortcode": ":shortcode: stays literal -> use the emoji character or nothing",
}

DESCRIPTION_ERRORS = {
    "md-heading": "Markdown heading in wiki markup -> h2. Title",
    "md-bold": "**bold** is not wiki markup -> *bold*",
    "md-backtick": "backticks are not wiki markup -> {{code}}",
    "md-link": "[text](url) is not wiki markup -> [text|url]",
    "md-fence": "``` is not wiki markup -> {code:lang} ... {code}",
}

FENCE_RE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
ICON_RE = re.compile(r"\((?:i|y|n|on|off|x|/|!|\?|\+|-|\*[rgby]?|flag|flagoff)\)")
UNDERLINE_RE = re.compile(r"(?<![\w+])\+[^\s+][^+\n]*?(?<!\s)\+(?![\w+])")
MENTION_RE = re.compile(r"(?<![\w.@/])@[A-Za-z][\w.-]*")
SHORTCODE_RE = re.compile(r"(?<![\w:/]):[a-z0-9_+-]+:(?![\w/])")
RULE_RE = re.compile(r"^\s*([-*_=])(\s*\1){2,}\s*$")
SEPARATOR_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$")
LINK_RE = re.compile(r"\[((?:[^\[\]]|\[[^\]]*\])*)\]\(([^)\n]*\)?[^)\n]*)\)")


def _without_code(line):
    return INLINE_CODE_RE.sub("", line)


def _link_is_bad(line):
    for match in LINK_RE.finditer(line):
        text, url = match.group(1), match.group(2)
        if "[" in text or "]" in text or "(" in url or "__" in url or re.search(r"\s\"", url):
            return True
    return False


def _stray_stars(line):
    return line.replace("**", "").count("*") >= 2


def lint_comment(text):
    warnings = []

    def error(n, code):
        warnings.append(Warning(n, "error", code, ERRORS[code]))

    def note(n, code):
        warnings.append(Warning(n, "note", code, NOTES[code]))

    in_fence = False
    fence_first = False
    for n, raw in enumerate(text.split("\n"), start=1):
        line = raw.rstrip("\r")
        fence = FENCE_RE.match(line)
        if fence:
            if not in_fence:
                lang = line.strip()[3:]
                if fence.group(1) == "~~~" or (lang and not re.fullmatch(r"\w+", lang)) or raw.endswith("\r"):
                    error(n, "bad-fence")
                in_fence, fence_first = True, True
            else:
                in_fence = False
            continue

        if "??" in line:
            error(n, "double-question")
        if re.search(r"<[^>\n]+>", line):
            error(n, "angle-brackets")
        if re.search(r"__[^_\s][^_]*?__", line):
            error(n, "dunder")
        if _stray_stars(line) and not re.match(r"^\s*\*\s", line):
            error(n, "stray-stars")

        if in_fence:
            if re.match(r"^\s*([-*] |\|)", line) or (line.lstrip().startswith("#") and not fence_first):
                error(n, "fence-content")
            fence_first = False
            continue

        if re.match(r"^\s*\*\s", line) and ("**" in line or "__" in line):
            error(n, "star-bullet-bold")
        if re.match(r"^[ \t]+[-*+] ", line):
            error(n, "indented-bullet")
        if re.match(r"^\*[-#]\s", line) and ("**" in line or "__" in line):
            error(n, "nested-bold")
        if re.match(r"^[ \t]+\d+\. ", line):
            error(n, "indented-number")
        if re.match(r"^#+[^#\s]", line):
            error(n, "hash-no-space")
        if RULE_RE.match(line) and not re.fullmatch(r"----[ \t]+", line):
            error(n, "rule-line")
        if re.match(r"^\s*>", line):
            error(n, "md-quote")
        if re.search(r"!\[[^\]]*\]\(", line):
            error(n, "md-image")
        if _link_is_bad(line):
            error(n, "bad-link")
        if SEPARATOR_RE.match(line):
            if ":" in line:
                error(n, "table-align")
            elif not line.strip().startswith("|"):
                error(n, "table-no-pipes")
        if re.match(r"^\s*[-*] \[[ xX]\]", line):
            error(n, "task-box")

        prose = _without_code(line)
        if ICON_RE.search(prose):
            note(n, "icon")
        if UNDERLINE_RE.search(prose):
            note(n, "underline")
        if MENTION_RE.search(prose):
            note(n, "at-mention")
        if SHORTCODE_RE.search(prose):
            note(n, "shortcode")
    return warnings


def lint_description(text):
    warnings = []

    def error(n, code):
        warnings.append(Warning(n, "error", code, DESCRIPTION_ERRORS[code]))

    lines = text.split("\n")
    hash_line = [bool(re.match(r"^#{1,6}\s", line)) for line in lines]
    for n, line in enumerate(lines, start=1):
        if re.match(r"^\s*```", line):
            error(n, "md-fence")
            continue
        lone = hash_line[n - 1] and not (n > 1 and hash_line[n - 2]) and not (n < len(lines) and hash_line[n])
        if lone:
            error(n, "md-heading")
        if re.search(r"\*\*[^*\n]+\*\*", line):
            error(n, "md-bold")
        if re.search(r"(?<!`)`[^`\n]+`(?!`)", line):
            error(n, "md-backtick")
        if re.search(r"\[[^\]|\n]+\]\([^)\n]+\)", line):
            error(n, "md-link")
    return warnings


def docker_convert(text, image):
    try:
        result = subprocess.run(
            ["docker", "run", "--rm", "-i", "--entrypoint", "/app/.venv/bin/python", image, "-c", CONVERT_CODE],
            input=text, capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ConversionError(str(e)) from e
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else f"exit {result.returncode}"
        raise ConversionError(detail)
    return result.stdout


def main(argv=None, stdin=None, stdout=None, stderr=None, runner=docker_convert):
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    parser = argparse.ArgumentParser(
        prog="jira_preview.py",
        description="Show what Jira will receive from the mcp-atlassian tools, and flag what breaks.",
    )
    parser.add_argument("file", nargs="?", help="Markdown draft of a comment (wiki markup with --description); stdin if omitted")
    parser.add_argument("--description", action="store_true", help="lint wiki markup meant for a description field; no conversion")
    parser.add_argument("--no-convert", action="store_true", help="only lint; do not run the converter")
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0

    if args.file:
        with open(args.file, encoding="utf-8", newline="") as f:
            text = f.read()
    else:
        text = stdin.read()

    if args.description:
        warnings = lint_description(text)
        stdout.write(text)
    else:
        warnings = lint_comment(text)
        if args.no_convert:
            stdout.write(text)
        else:
            try:
                stdout.write(runner(text, os.environ.get("JIRA_MCP_IMAGE", DEFAULT_IMAGE)))
            except ConversionError as e:
                stderr.write(f"conversion skipped ({e}); showing the draft as written\n")
                stdout.write(text)

    for w in sorted(warnings, key=lambda w: (w.line, w.severity)):
        stderr.write(f"line {w.line}: {w.severity}: {w.message}\n")
    n_errors = sum(1 for w in warnings if w.severity == "error")
    if warnings:
        stderr.write(f"{n_errors} error(s), {len(warnings) - n_errors} note(s)\n")
    return 1 if n_errors else 0


if __name__ == "__main__":
    sys.exit(main())
