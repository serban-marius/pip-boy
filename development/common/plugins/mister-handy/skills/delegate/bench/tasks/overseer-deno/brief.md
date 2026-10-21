# overseer-deno: deno test and deno task test count as test runs

## Why
A Deno repo ran its tests green with `deno test` and `deno task test`, and overseer still blocked
the commit with "not a green" because it did not recognise either command as a test runner.

## What we already know
- Plugin: `development/common/plugins/overseer/` (version 0.1.1). The hook is
  `hooks/overseer.sh`; it never learns the test command, it matches Bash commands against a fixed
  list of test runners (the `TESTS` regex) and logs a failing run as red, a passing one as green.
- Its tests: `bash development/common/plugins/overseer/hooks/overseer.test.sh` (needs `jq`).
- The README lists the recognised runners under "How it knows".

## Task
- `deno test` (with any flags or paths, also when it is part of a longer command such as
  `docker run --rm -v "$PWD":/w -w /w denoland/deno:alpine-2.0.6 deno test --allow-all src/`) and
  `deno task test` count as test runs.
- README: add `deno test` to the list of runners.
- Bump overseer to 0.1.2 in its `plugin.json` and in `.claude-plugin/marketplace.json`.

## Acceptance
- After a production edit, a green `deno test ...` run, or a green `deno task test` run, lets the
  next `git commit` through (exit 0 from the pre-bash hook).
- Cover both in `overseer.test.sh`; the whole file is green.
- Commit message in the repo's style, e.g. `fix(overseer): ... (0.1.2)`.
