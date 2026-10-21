# bench: cheap workers against Claude workers on real past tasks

Replays merged pip-boy work as worker briefs. Each run starts from the commit before the work, gives
an arm the brief exactly as HQ would launch a worker, then runs the tests the merged commit added
(hidden from the worker) and scores the reporting protocol.

## Run

```bash
bash bench/run.sh <task-id> <arm> [rep]          # one run, one line in results/results.jsonl
bash bench/campaign.sh <parallel> <reps> <arm>…  # every task × arm × rep not in the results yet
bash bench/report.sh > bench/RESULTS.md          # tables, only from results.jsonl (+ results/jev.jsonl)
bash bench/jev.sh <cheap-mvp delegate dir>       # Jev's and route.sh's pick per task -> results/jev.jsonl
bash bench/validate.sh [task-id…]                # each check fails on its base and passes on its merged commit
```

Arms:

| Arm | Launch |
|---|---|
| `claude-<model>` | `claude -p --model <model> --permission-mode auto --output-format stream-json --verbose` (the user's plugins and hooks load, as for a real worker) |
| `pi-<nan model id>` | `pi -p --no-session --mode json --model nan/<id>` (the user's pi extensions load) |
| `pi-<nan model id>-ne` | same with `--no-extensions` |
| `pipeline` | `BENCH_PIPELINE='bash bench/pipeline.sh "$@"' BENCH_CHEAP_DIR=<delegate dir>`: route.sh, then foreman.sh or a Claude worker, escalation included |

Limits used for the published numbers: ≤3 pi runs and ≤2 Claude runs at once (NAN throttles),
25 min per run (`BENCH_TIMEOUT`, seconds).

A run lives in a temp dir laid out like HQ's: `<tmp>/_hq/STATUS.md`, `<tmp>/_hq/briefs/<task>.md`,
`<tmp>/<task>/` (the repo), `<tmp>/origin.git` (a local bare remote, so a push is detected and goes
nowhere). The repo is a fresh `git init` that fetches only the base commit: the merged commit and
its tests are not in its object store. Child processes run without the parent's `ORCA_*` and
Claude Code session variables. The temp dir is removed after scoring; the scrubbed agent log
(`results/logs/<task>__<arm>__<rep>.log.gz`) and STATUS + check output + diff (`.txt`) are kept,
gitignored.

## Result line

`pass` (hidden tests exit 0), `tests_passed/tests_total/tests_base` and `new_tests_frac` (share of
the tests the base did not already pass), `wall_s`, `exit`, `timed_out`, `cost_usd` and `tokens`
(Claude from the stream's `result` event; NAN summed from pi's `message_end` usage, `cost_usd` 0),
`turns`, `errors`, `http429`, and `protocol`:

| Field | Meaning |
|---|---|
| `start` | a well-formed `HH:MM <task> START` line |
| `done` | `HH:MM <task> DONE <sha>` with a sha of a new commit on the branch (`done_is_head`: it is HEAD) |
| `final` | last of DONE / FAILED / BLOCKED, or `none` |
| `malformed_lines` | STATUS lines not in `HH:MM <task> <STATE> ...` form |
| `commits`, `dirty_files` | commits made; tracked files left uncommitted |
| `pushed`, `pr_attempt` | the bare remote changed; a `gh pr create/merge` command ran |
| `bare_stash` | a `git stash` other than `push -m`/`list`/`show`/`apply`/`drop`, or a stash left behind |
| `stray` | untracked or ignored files left in the repo (not `__pycache__`), committed `.atl/`, extra files next to the repo or in `_hq/` |
| `out_of_scope` | changed paths outside `tasks/<id>/scope` |

`protocol_score` = share of: START, DONE, a commit, no push/PR, no bare stash, no stray files.

## Add a task

1. Pick a merged commit whose tests pin its behaviour. `tasks/<id>/base` = its parent sha.
2. `tasks/<id>/brief.md`: Why / What we already know / Task / Acceptance, written as HQ would
   brief a worker. Everything the hidden test asserts (names, exact output strings, interfaces)
   must be in the brief; how to get there must not. Never paste the test. `run.sh` appends the
   Rules and Reporting sections.
3. `tasks/<id>/check.sh`: `hidden <merged sha> <test path>` then `run_bash_test` or `run_unittest`
   (see `lib.sh`); add other runners there, printing `BENCH-SCORE <passed> <total>`.
4. `tasks/<id>/scope` (path prefixes the work may touch), `accept` (the visible acceptance
   commands, for the pipeline brief), `risk` (`low` / `normal`), optional `prepare.sh <repo>`
   (commits extra base state, such as docs that landed with the work).
5. `bash bench/validate.sh <id>` must print `base exit=1` and `merged exit=0`; it writes
   `tasks/<id>/tests`. Add the id to `tasks/order`.
