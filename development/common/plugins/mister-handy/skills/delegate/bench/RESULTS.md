# Bench results

76 runs, 6 tasks, 8 arms. Each task × arm × rep counts its first attempt that was not cut short by NAN throttling or an API error (5 such attempts re-run, not counted; 13 later attempts of an already counted run, not counted either; 0 superseded by a harness change and re-run). Cell: passes/runs (mean fraction of the merged commit's new tests passing).

## Pass rate by task × arm

| task | claude-opus | claude-sonnet | pi-deepseek-v4-flash | pi-glm5.3-flash | pi-glm5.3-flash-ne | pi-mimo-v2.6-flash | pi-qwen3.8-flash | pipeline |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| overseer-deno | 1/1 (1) | 1/1 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) |
| overseer-worktree | 1/1 (1) | 1/1 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 1/1 (1) |
| jira-length | 1/1 (1) | 1/1 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 1/2 (0.5) | 1/1 (1) |
| close-worktrees | 1/1 (1) | 1/1 (1) | 2/2 (1) | 1/2 (0.84) | 1/2 (0.95) | 0/2 (0.45) | 2/2 (1) | – |
| reachable-workers | 1/1 (1) | 1/1 (1) | 2/2 (1) | 2/2 (1) | 2/2 (1) | 0/2 (0) | 2/2 (1) | – |
| jira-preview | 1/1 (1) | 1/1 (1) | 2/2 (1) | 0/2 (0) | 0/2 (0.48) | 0/2 (0) | 1/2 (0.99) | – |

## Median wall time (s)

| task | claude-opus | claude-sonnet | pi-deepseek-v4-flash | pi-glm5.3-flash | pi-glm5.3-flash-ne | pi-mimo-v2.6-flash | pi-qwen3.8-flash | pipeline |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| overseer-deno | 54 | 57 | 189.5 | 136.5 | 115.5 | 363 | 224.5 | 140 |
| overseer-worktree | 345 | 52 | 317 | 274 | 295.5 | 1035.5 | 1152 | 431 |
| jira-length | 339 | 62 | 339 | 484 | 385.5 | 1337.5 | 924.5 | 310 |
| close-worktrees | 503 | 119 | 433 | 1082.5 | 748.5 | 1086 | 1049 | – |
| reachable-workers | 478 | 327 | 1216 | 919 | 820.5 | 1082 | 648.5 | – |
| jira-preview | 1022 | 181 | 454.5 | 676 | 831.5 | 634 | 1497.5 | – |

## Cost per run (Claude: total USD for the task's runs; NAN: median tokens per run, quota not money)

| task | claude-opus | claude-sonnet | pi-deepseek-v4-flash | pi-glm5.3-flash | pi-glm5.3-flash-ne | pi-mimo-v2.6-flash | pi-qwen3.8-flash | pipeline |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| overseer-deno | $0.43 | $0.17 | 1M | 460k | 226k | 680k | 651k | 0k |
| overseer-worktree | $2.62 | $0.23 | 1.7M | 522k | 378k | 1.3M | 3.4M | 0k |
| jira-length | $3.03 | $0.27 | 3.2M | 1.2M | 702k | 2.2M | 3.7M | 0k |
| close-worktrees | $3.29 | $0.4 | 3M | 2.3M | 1.2M | 1.1M | 4.1M | – |
| reachable-workers | $3.37 | $0.38 | 2.8M | 1.9M | 1.1M | 936k | 1.5M | – |
| jira-preview | $6.23 | $0.54 | 3.4M | 280k | 776k | 207k | 5.1M | – |

## Per arm

| arm | runs | pass | new tests | median s | Claude $ | median tokens | protocol | START ok | DONE ok | stray files | out of scope | timeouts | hit output cap | runs with errors | 429s | throttled, re-run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus | 6 | 6 (100%) | 1 | 411.5 | $18.96 | 1.2M | 0.97 | 100% | 100% | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| claude-sonnet | 6 | 6 (100%) | 1 | 90.5 | $1.99 | 445k | 1 | 100% | 100% | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| pi-deepseek-v4-flash | 12 | 12 (100%) | 1 | 339 | – | 2.2M | 0.82 | 100% | 92% | 12 | 8 | 1 | 0 | 0 | 0 | 2 |
| pi-glm5.3-flash | 12 | 9 (75%) | 0.81 | 599.5 | – | 917k | 0.64 | 50% | 67% | 12 | 8 | 1 | 2 | 1 | 3 | 1 |
| pi-glm5.3-flash-ne | 12 | 9 (75%) | 0.9 | 520.5 | – | 679k | 0.92 | 67% | 92% | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| pi-mimo-v2.6-flash | 12 | 6 (50%) | 0.57 | 795 | – | 972k | 0.64 | 100% | 42% | 12 | 8 | 3 | 4 | 1 | 0 | 0 |
| pi-qwen3.8-flash | 12 | 10 (83%) | 0.91 | 903.5 | – | 3.3M | 0.75 | 92% | 67% | 12 | 8 | 2 | 0 | 1 | 0 | 2 |
| pipeline | 4 | 4 (100%) | 1 | 242.5 | – | 0k | 1 | 100% | 100% | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

## Jev pick vs best cheapest passing arm

Best cheapest passing arm: the cheapest tier (NAN < Sonnet < Opus) with an arm passing at least half its runs; within the tier, the highest pass rate, then the fastest. Jev = raw answer to route.sh's question; route.sh = what cheap-mvp's router finally picks (its pre-checks and confidence threshold included).

| task | best cheapest passing | Jev | route.sh | Jev tier right? |
|---|---|---|---|---|
| overseer-deno | pi-glm5.3-flash-ne (2/2) | nan-flash 0.92 | pi nan/glm5.3-flash 0.92 jev | yes |
| overseer-worktree | pi-glm5.3-flash (2/2) | claude-sonnet 0.45 | claude opus 0.40 low-confidence:claude-sonnet | no, over-spends |
| jira-length | pi-deepseek-v4-flash (2/2) | nan-flash 0.49 | claude sonnet 0.45 low-confidence:nan-flash | yes |
| close-worktrees | pi-deepseek-v4-flash (2/2) | claude-sonnet 0.76 | claude sonnet 0.72 jev | no, over-spends |
| reachable-workers | pi-qwen3.8-flash (2/2) | claude-sonnet 0.64 | claude sonnet 0.69 jev | no, over-spends |
| jira-preview | pi-deepseek-v4-flash (2/2) | claude-sonnet 0.58 | claude sonnet 0.61 jev | no, over-spends |

## Escalation ladder, simulated from these pass rates

Ladder: pi-glm5.3-flash-ne×2 → pi-deepseek-v4-flash×1 → claude-sonnet×1 → claude-opus×1. Each try passes with the arm's observed pass rate on that task (independent tries: optimistic for a model that fails the same way twice). Baseline: every task on claude-opus once.

| task | P(done by NAN) | P(done) ladder | P(done) opus only | expected Claude $ ladder | Claude $ opus only |
|---|---|---|---|---|---|
| overseer-deno | 100% | 100% | 100% | $0 | $0.43 |
| overseer-worktree | 100% | 100% | 100% | $0 | $2.62 |
| jira-length | 100% | 100% | 100% | $0 | $3.03 |
| close-worktrees | 100% | 100% | 100% | $0 | $3.29 |
| reachable-workers | 100% | 100% | 100% | $0 | $3.37 |
| jira-preview | 100% | 100% | 100% | $0 | $6.23 |
| **all** | 100% | 100% | 100% | $0 | $18.96 |

## Pipeline arms (route.sh + foreman.sh, ESCALATE ends the run)

`pipeline` = foreman.sh's default ladder; `pipeline-<name>` = the ladder in `bench/ladders/<name>`. Escalated runs are not re-run on Claude: "then on Sonnet" is the claude-sonnet arm's pass rate on that task, and its cost is the Claude spend the escalation would add. route.sh = its pick on the pipeline brief (one Jev call, 0 Claude tokens; the run goes to foreman whatever it picks). NAN tokens = all pi sessions of the run (attempts and 429 retries). Output cap = pi sessions whose last turn ended with stopReason `length`.

### Side by side

| arm | ladder | runs | DONE + hidden pass | DONE, hidden fail | killed at timeout | escalated | effective pass (escalations on Sonnet) | median s | median NAN tokens | attempts (mean) | output-cap sessions | Claude $ (escalations on Sonnet) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pipeline | default | 4 | 4 | 0 | 0 | 0 (0%) | 4/4 (100%) | 242.5 | – | 1 | – | $0 |

### Per task

| task | arm | runs | DONE + hidden pass | DONE, hidden fail | killed at timeout | escalated | effective pass | median s | median NAN tokens | attempts (mean) | output-cap sessions | Claude $ | route.sh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| overseer-deno | pipeline | 2 | 2 | 0 | 0 | 0 (0%) | 2/2 (100%) | 140 | – | 1 | – | $0 | pi nan/glm5.3-flash jev ×2 |
| overseer-worktree | pipeline | 1 | 1 | 0 | 0 | 0 (0%) | 1/1 (100%) | 431 | – | 1 | – | $0 | claude opus low-confidence:claude-sonnet ×1 |
| jira-length | pipeline | 1 | 1 | 0 | 0 | 0 (0%) | 1/1 (100%) | 310 | – | 1 | – | $0 | claude sonnet low-confidence:nan-flash ×1 |

### Output cap per attempt model

| arm | model | pi sessions | ended on output cap | turns cut by the cap |
|---|---|---|---|---|
