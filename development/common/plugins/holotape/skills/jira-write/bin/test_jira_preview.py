import io
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import jira_preview as jp

FENCE = "`" * 3


def codes(warnings):
    return {(w.line, w.code) for w in warnings}


def errors(warnings):
    return [w for w in warnings if w.severity == "error"]


class CommentErrors(unittest.TestCase):
    def assertFlags(self, text, line, code):
        found = codes(jp.lint_comment(text))
        self.assertIn((line, code), found, f"{code} not flagged at line {line}; got {sorted(found)}")

    def test_star_bullet_with_bold(self):
        self.assertFlags("intro\n* **Label:** text", 2, "star-bullet-bold")

    def test_indented_bullet(self):
        self.assertFlags("- parent\n  - child", 2, "indented-bullet")
        self.assertFlags("- parent\n\t- child", 2, "indented-bullet")

    def test_nested_line_with_bold(self):
        self.assertFlags("- parent\n*- **Label:** child", 2, "nested-bold")
        self.assertFlags("- parent\n*# **Label:** child", 2, "nested-bold")

    def test_indented_number(self):
        self.assertFlags("1. first\n   1. sub", 2, "indented-number")

    def test_hash_without_space(self):
        self.assertFlags("#39 is merged", 1, "hash-no-space")

    def test_rule_lines(self):
        for rule in ("---", "***", "===", "----", "___"):
            self.assertFlags(f"above\n\n{rule}\n\nbelow", 3, "rule-line")

    def test_rule_with_trailing_space_is_the_way(self):
        self.assertEqual(jp.lint_comment("above\n---- \nbelow"), [])
        self.assertIn("'---- '", jp.lint_comment("above\n----\nbelow")[0].message)

    def test_angle_brackets(self):
        self.assertFlags("returns List<String> today", 1, "angle-brackets")
        self.assertFlags("if a < b and c > d", 1, "angle-brackets")
        self.assertFlags("see <https://example.com>", 1, "angle-brackets")

    def test_dunder(self):
        self.assertFlags("call __init__ first", 1, "dunder")

    def test_stray_stars(self):
        self.assertFlags("2 * 3 * 4", 1, "stray-stars")
        self.assertFlags("matches *.log and *.tmp", 1, "stray-stars")

    def test_markdown_quote(self):
        self.assertFlags("> quoted", 1, "md-quote")

    def test_markdown_image(self):
        self.assertFlags("![diagram](https://example.com/a.png)", 1, "md-image")

    def test_bad_links(self):
        self.assertFlags("[wiki](https://en.wikipedia.org/wiki/Foo_(bar))", 1, "bad-link")
        self.assertFlags("[docs](https://example.com/a__b__c)", 1, "bad-link")
        self.assertFlags('[t](https://example.com "title")', 1, "bad-link")
        self.assertFlags("[[WIP] title](https://example.com/1)", 1, "bad-link")

    def test_table_alignment_and_missing_pipes(self):
        self.assertFlags("| A | B |\n|:--|--:|\n| 1 | 2 |", 2, "table-align")
        self.assertFlags("A | B\n--- | ---\n1 | 2", 2, "table-no-pipes")

    def test_bad_fences(self):
        self.assertFlags(f"{FENCE}c++\nint x;\n{FENCE}", 1, "bad-fence")
        self.assertFlags("~~~\ncode\n~~~", 1, "bad-fence")
        self.assertFlags(f"{FENCE}php\r\n$a;\r\n{FENCE}", 1, "bad-fence")

    def test_fence_content_rewritten(self):
        text = f"{FENCE}bash\n# first line is kept\ncomposer install\n# comment\n- not a list\n{FENCE}"
        found = codes(jp.lint_comment(text))
        self.assertNotIn((2, "fence-content"), found)
        self.assertIn((4, "fence-content"), found)
        self.assertIn((5, "fence-content"), found)

    def test_task_box(self):
        self.assertFlags("- [ ] todo", 1, "task-box")

    def test_double_question_hangs_the_mcp(self):
        self.assertFlags("why?? because", 1, "double-question")
        self.assertFlags("quoted ??Some Author??", 1, "double-question")
        self.assertFlags("run `a??b`", 1, "double-question")
        self.assertFlags(f"{FENCE}\nx = a ?? b\n{FENCE}", 2, "double-question")

    def test_single_question_marks_are_fine(self):
        self.assertEqual(jp.lint_comment("is it done? yes? (?) maybe"), [w for w in jp.lint_comment("is it done? yes? (?) maybe") if w.code == "icon"])


class CommentNotes(unittest.TestCase):
    def test_icons_are_notes(self):
        warnings = jp.lint_comment("option (i) and (y) and (on)")
        self.assertIn((1, "icon"), codes(warnings))
        self.assertEqual(errors(warnings), [])

    def test_underline_mention_shortcode_are_notes(self):
        warnings = jp.lint_comment("a +b+ c\ncc @sam\n:white_check_mark: done")
        self.assertEqual(codes(warnings), {(1, "underline"), (2, "at-mention"), (3, "shortcode")})
        self.assertEqual(errors(warnings), [])

    def test_notes_skip_code(self):
        text = f"run `(x) @me :tag:`\n{FENCE}\nprint('(i) @a +b+')\n{FENCE}"
        self.assertEqual(jp.lint_comment(text), [])

    def test_no_false_notes(self):
        text = "C++ and 1 + 2 + 3, at 10:30:00, mail me@example.com, https://x.io/a"
        self.assertEqual(jp.lint_comment(text), [])


class CommentClean(unittest.TestCase):
    def test_safe_subset(self):
        text = "\n".join([
            "**Done: deployed (30/09)**",
            "",
            "### Details",
            "- **Label:** text with `snake_case` and [PR #39](https://github.com/o/r/pull/39)",
            "- parent",
            "*- child with `code` and [link](https://example.com/a)",
            "*# numbered child",
            "1. first",
            "2. second",
            "",
            "| Check | Result |",
            "|-------|--------|",
            "| Unit | `pass` |",
            "",
            "{quote}",
            "quoted text",
            "{quote}",
            "{panel:bgColor=#deebff}",
            "### Panel",
            "- item",
            "{panel}",
            "Blocked by PROJ-123, rated 5* by users.",
        ])
        self.assertEqual(jp.lint_comment(text), [])

    def test_parenthesis_after_a_link_is_not_part_of_it(self):
        self.assertEqual(jp.lint_comment("- [PR #215](https://github.com/o/r/pull/215) (purge endpoint) waits"), [])

    def test_empty_angle_pair_is_left_alone(self):
        self.assertEqual(jp.lint_comment("choose <> or not"), [])

    def test_templates_have_no_errors(self):
        templates = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "templates.md")
        with open(templates, encoding="utf-8") as f:
            content = f.read()
        comments, descriptions = content.split("## Descriptions")
        comment_blocks = re.findall(r"### (.+?)\n.*?" + FENCE + r"markdown\n(.*?)" + FENCE, comments, re.S)
        description_blocks = re.findall(r"### (.+?)\n.*?" + FENCE + r"\n(.*?)" + FENCE, descriptions, re.S)
        self.assertGreaterEqual(len(comment_blocks), 5)
        self.assertGreaterEqual(len(description_blocks), 3)
        for name, body in comment_blocks:
            self.assertEqual(errors(jp.lint_comment(body)), [], name)
        for name, body in description_blocks:
            self.assertEqual(jp.lint_description(body), [], name)

    def skill_examples(self):
        skill = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SKILL.md")
        with open(skill, encoding="utf-8") as f:
            content = f.read()
        return re.findall(FENCE + r"markdown\n(.*?)" + FENCE, content, re.S)

    def test_skill_good_example_is_clean(self):
        too_long, good = self.skill_examples()[:2]
        self.assertEqual(jp.lint_comment(good), [])

    def test_skill_too_long_example_is_noted(self):
        too_long, good = self.skill_examples()[:2]
        found = {w.code for w in jp.lint_comment(too_long)}
        self.assertIn("long-headline", found)
        self.assertIn("long-bullet", found)
        self.assertEqual(errors(jp.lint_comment(too_long)), [])


class Length(unittest.TestCase):
    def test_long_bullet_is_a_note(self):
        warnings = jp.lint_comment("- " + "word " * 30)
        self.assertEqual(codes(warnings), {(1, "long-bullet")})
        self.assertEqual(errors(warnings), [])

    def test_bullet_at_the_limit_is_fine(self):
        self.assertEqual(jp.lint_comment("- " + "x" * 118), [])

    def test_long_bold_headline_is_a_note(self):
        warnings = jp.lint_comment("**" + "a very long headline that keeps going " * 3 + "**\n\n- ok")
        self.assertIn((1, "long-headline"), codes(warnings))
        self.assertEqual(errors(warnings), [])

    def test_short_headline_and_plain_first_line_are_fine(self):
        self.assertEqual(jp.lint_comment("**In production (v2.4.0), ready to test**"), [])
        self.assertEqual(jp.lint_comment("A plain first line that is rather long but not a bold headline at all, fine."), [])

    def test_list_of_five_is_a_note_on_its_fifth_item(self):
        text = "intro\n" + "\n".join(f"- item {i}" for i in range(1, 6))
        self.assertEqual(codes(jp.lint_comment(text)), {(6, "long-list")})

    def test_list_of_four_and_separate_lists_are_fine(self):
        self.assertEqual(jp.lint_comment("\n".join(f"- item {i}" for i in range(1, 5))), [])
        two_lists = "- a\n- b\n- c\n\n**Next**\n- d\n- e"
        self.assertEqual(jp.lint_comment(two_lists), [])

    def test_thumbnail_image_is_a_note(self):
        self.assertEqual(codes(jp.lint_comment("!shot.png|thumbnail!")), {(1, "thumbnail-image")})
        self.assertEqual(jp.lint_comment("!shot.png|width=800!"), [])


class Description(unittest.TestCase):
    def test_flags_markdown(self):
        text = "## Context\n**bold** and `code`\n[text](https://x.io)\n" + FENCE + "\nx\n" + FENCE
        found = codes(jp.lint_description(text))
        self.assertTrue({(1, "md-heading"), (2, "md-bold"), (2, "md-backtick"), (3, "md-link"), (4, "md-fence")} <= found, found)

    def test_lone_hash_line_is_a_heading_list_is_not(self):
        self.assertIn((2, "md-heading"), codes(jp.lint_description("intro\n# Heading\ntext")))
        self.assertEqual(jp.lint_description("# one\n# two"), [])

    def test_clean_wiki(self):
        text = "\n".join([
            "{panel:bgColor=#deebff}",
            "h3. *CONTEXT*",
            "* *Case A:* rejected",
            "** nested",
            "# numbered one",
            "# numbered two",
            "## numbered child",
            "{{code}} and [text|https://x.io]",
            "||Head||Head||",
            "|a|b|",
            "{panel}",
        ])
        self.assertEqual(jp.lint_description(text), [])


class Cli(unittest.TestCase):
    def run_main(self, argv, stdin):
        out, err = io.StringIO(), io.StringIO()
        code = jp.main(argv, io.StringIO(stdin), out, err)
        return code, out.getvalue(), err.getvalue()

    def test_no_convert_with_errors(self):
        code, out, err = self.run_main(["--no-convert"], "intro\n  - child\n")
        self.assertEqual(code, 1)
        self.assertEqual(out, "intro\n  - child\n")
        self.assertIn("line 2: error:", err)

    def test_no_convert_clean(self):
        code, out, err = self.run_main(["--no-convert"], "- fine\n")
        self.assertEqual(code, 0)
        self.assertEqual(out, "- fine\n")

    def test_notes_do_not_fail(self):
        code, _, err = self.run_main(["--no-convert"], "(/) deployed\n")
        self.assertEqual(code, 0)
        self.assertIn("line 1: note:", err)

    def test_description_mode(self):
        code, out, err = self.run_main(["--description"], "## Title\n")
        self.assertEqual(code, 1)
        self.assertEqual(out, "## Title\n")
        self.assertIn("line 1: error:", err)

    def test_convert_uses_runner(self):
        calls = []

        def runner(text, image):
            calls.append((text, image))
            return "* converted\n"

        out, err = io.StringIO(), io.StringIO()
        code = jp.main([], io.StringIO("- item\n"), out, err, runner=runner)
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "* converted\n")
        self.assertEqual(calls[0][0], "- item\n")

    def test_convert_failure_still_lints(self):
        def runner(text, image):
            raise jp.ConversionError("docker: command not found")

        out, err = io.StringIO(), io.StringIO()
        code = jp.main([], io.StringIO("  - child\n"), out, err, runner=runner)
        self.assertEqual(code, 1)
        self.assertIn("conversion skipped", err.getvalue())
        self.assertIn("line 1: error:", err.getvalue())


if __name__ == "__main__":
    unittest.main()
