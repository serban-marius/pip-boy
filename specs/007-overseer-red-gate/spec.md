# 007 · overseer red gate: interpreter writes, masked exits and more runners

## Why

Overseer 0.2.0 lost a worker about six minutes on review-generator. Three holes in the red gate
caused it, and the block message did not say what the hook had seen.

1. Production code written through an interpreter in Bash was invisible. `pre-bash` only looked at
   shell writes, and it stripped heredocs and quoted arguments before scanning, so
   `python - <<EOF ... open('src/A.php', 'w') ... EOF` never reached the production gate.
2. A failing test whose exit was masked by `; echo $?`, `| tail` or `|| true` was logged green.
   `post-bash` never read the runner's output or the exit code, and `PostToolUseFailure` only sees
   commands that actually failed.
3. `TESTS` did not know `paratest`, `composer unit-tests`, `composer run-script tests` or
   `make unit-tests`, the usual Laravel runners, nor this repo's own `bash .../x.test.sh` and
   `python3 .../test_x.py` suites.

## What changes

| Case | Today | After |
|---|---|---|
| Interpreter writes | `python -c`, `python - <<EOF`, `php -r`, `node -e`, `ruby -e` write production files unseen | A separate pre-bash trigger recognises those inline-code forms (`-c`, `-e`, `-r`, `-`, heredoc or here-string on stdin) and scans the raw code before heredoc/quote stripping. Literal paths from Python `open(..., 'w'/'a'/'x'/'+')`, `Path.write_text/write_bytes`, `shutil.copy*/move`, `os.rename/replace`; PHP `file_put_contents`, `fopen(..., 'w'/'a'/'x'/'c'/'+')`, `copy`, `rename`; Node `fs.writeFile(Sync)`, `appendFile(Sync)`, `createWriteStream`, `copyFile`, `rename`; Ruby `File.write`, `File.open(..., 'w'/'a'/'+')`, `IO.write`, `FileUtils.cp/mv` go through the same spec/red gate as Edit/Write, and `.git/overseer` paths through the state-dir guard. A write API whose path is not a string literal is blocked and names the API and Edit/Write. Reads are free. A non-literal mode argument is skipped because the call is not confirmed as a write, and the mode must be a real mode string. A bare `copy(`/`rename(` counts only as a function call, or on an `fs`/`require('fs')` receiver, with at least two arguments; object methods such as `d.copy()` and `df.rename(columns=...)` are free, and `.open(` counts only on `File`. Running a script file (`python3 tools/gen.py`) stays out of scope. |
| Verdict | any `PostToolUse` test command logs green; only `PostToolUseFailure` logs red | On a test command, `post-bash` reads `tool_response.stdout` and `tool_response.stderr` (missing, string or object). A failure verdict is red, a pass verdict green. With no verdict, a bare command is green as before; a command whose exit is masked (`||`, a lone `|`/`|&` without `pipefail`, or `;`/newline after the test match) logs nothing and says on stderr that the run was not counted and to run the test bare. `bash-failed` stays red. Verdicts: PHPUnit/paratest/pest `FAILURES!`/`ERRORS!` vs `OK (`; pytest `N failed`/`N error` vs `N passed`; jest/vitest `Tests: ... failed` vs `Tests: ... passed`; go `^FAIL`/`^--- FAIL` vs `^ok `; cargo `test result: FAILED` vs `test result: ok`; this repo's suites `N failed` vs `all green`. |
| Test runners | fixed list without Laravel or this repo's suites | `TESTS` adds `paratest`, `composer (run(-script)? )?[a-z-]*tests?`, `make [a-z-]*tests?`, and invocation-anchored `\.test\.sh` / `test_*.py` forms. Anchoring means `git add x.test.sh` or `cat x.test.sh` is not counted as a test run, while `bash .../overseer.test.sh` and `python3 bin/test_jira_preview.py` are. `bash-tests-own` uses the same regex, so a new runner chained into `git commit` is still blocked. |
| Block message | static "red first..." | An `edit-red`/`bash-red` block appends what the hook saw: `last test event: <green|red|none>` with its age (`Ns`, `Nmin`, `Nh`), whether it was `after your test edit` or `before any test edit`, and, for a green last event, a hint that a masked or passing run does not count as red and to run the failing test bare. |
| Version | 0.2.0 | 0.3.0 in `plugin.json` and the overseer entry in `marketplace.json`; README and `rules/overseer.md` describe the new gate. |

## How we'll know it works

`hooks/overseer.test.sh` gains cases, written first and seen failing:

- Python `-c`, Python heredoc, `Path.write_text`, PHP `-r file_put_contents`, Node `-e
  fs.writeFileSync` and Ruby `-e File.write` on a production file are blocked; a Python write to
  `.git/overseer/off` hits the state guard; Python reads, writes outside the repo and running a
  script file pass; a non-literal write path names its API and Edit/Write.
- PHPUnit `FAILURES!`/`ERRORS!` behind `| tail`, `; echo $?` and `|| true`, pytest, jest, go and
  cargo failures log red; passing output logs green; a masked run with no verdict logs neither and
  warns on stderr; a bare run with no output stays green; the string form of `tool_response` works;
  `bash-failed` stays red.
- `paratest`, the composer and make forms, and invocation-anchored this-repo runners count as test
  runs; `git add x.test.sh`/`cat x.test.sh` do not; chaining a new runner into `git commit` is
  blocked as `bash-tests-own`.
- `edit-red` with no test event says `last test event: none`; after a green run it carries the
  event, its age and the bare-run hint; after a red run it says red.

HQ's `_hq/assets/overseer-red-gate/accept.sh`, `overseer.test.sh`, `scripts/check-marketplace.sh`
and `vats.test.sh` all exit 0.
