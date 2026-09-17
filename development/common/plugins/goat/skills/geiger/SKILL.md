---
name: geiger
description: >
  Review the OUTPUTS of a developed feature (a PR/branch): did it work as intended, and did it
  introduce bugs. Phase 1 (pre-merge) runs the project tests + an adversarial review of the diff
  against the feature's acceptance criteria and posts a PR-comment verdict. Phase 2 (post-deploy)
  is a self-paced loop that orchestrates a deployment-aware set of regression lenses — error
  signatures, throughput/success rate, latency vs timeouts, cost, saturation, and the feature's
  business KPI — against a pre-deploy baseline for the feature's services, because a regression is
  not always a new error (it can be silence, slowness, or spend), and triages confirmed
  regressions to Jira (no Slack). Use when the user says "geiger",
  "review the outputs", "did my feature work", "check for regressions", "watch this PR after deploy",
  or "/geiger <pr|branch>". Natural continuation of goat after it ships a PR.
---

# Outcome Review

Review the **outputs** of one already-developed feature (a PR/branch) — not global telemetry,
not a channel, not an error stream. It answers two questions about that one change:

1. **Did it work as intended?** — an adversarial review of the diff against its acceptance
   criteria, run before merge.
2. **Did it introduce bugs — or silently stop working?** — the project's test suite (before
   merge) and, after deploy, a set of regression lenses (errors, throughput, latency, cost,
   saturation, business KPI) compared against a pre-deploy baseline. A regression is not always a
   new error: it can be a drop in output, a latency that crosses a timeout, or a cost spike — so
   Phase 2 picks lenses by *what was deployed* instead of only diffing error logs.

It is the natural continuation of the `goat` skill: that skill takes a ticket to a
shipped PR; `geiger` reviews what that work produced. **Phase 1 is generic** (any
stack, any repo — tests + adversarial review + PR comment). **Phase 2 is softonic-ES-specific**
(kubertonic-logs, Jira triage in project `DS`) — it orchestrates the lenses above and runs only
after you deploy.

> All `bin/` scripts referenced below live in this skill's directory. `BIN` stands for
> `${CLAUDE_PLUGIN_ROOT}/skills/geiger/bin` — resolve it once at the start of the
> session and invoke the scripts by that absolute path. ES credentials come from the user's
> `$ES_CREDS` environment variable (a `user:password` pair) — pass it as the first argument to
> `prod-delta.py` directly; never prompt the user to paste credentials when it is already set.

## Modes

```
/geiger <pr|branch>      # Phase 1: pre-merge review + capture pre-deploy baseline
/geiger --watch <pr>     # Phase 2: post-deploy loop (run AFTER you have deployed)
/geiger --status <pr>    # print loop state for that feature, exit
/geiger --stop <pr>      # release lock, exit the loop
```

Every mode is keyed by a stable `<key>` slug derived from the branch name: strip a leading
`feat/`, `fix/`, `chore/`, etc. prefix, e.g. `feat/DS-3671-foo` → `DS-3671-foo`. If a raw PR
number is given instead of a branch, resolve the branch first (`gh pr view <pr> --json
headRefName`) and derive the key from that. Use the SAME key for every `state.py` / lock /
baseline operation for a given feature across both phases and both sessions — that's what lets
Phase 2 find Phase 1's baseline.

---

## Phase 1 — Pre-merge review (generic, no production)

Runs against the CURRENT checked-out branch (or the branch resolved from a PR number).

1. **Resolve base + diff.** Determine the base branch:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@.*/@@')
   ```
   Fall back to the fork point (`git merge-base --fork-point origin/main`-style logic) if that
   fails — never hardcode `main`. Diff against the **merge-base**, not `$BASE` directly — a
   drifted local `$BASE` (behind origin) would otherwise inject reverse-direction noise from
   unrelated upstream commits. Capture the diff **once**, into a variable, so every later step
   reuses it instead of re-running git:
   ```bash
   git --no-pager diff $(git merge-base "$BASE" HEAD)
   ```

2. **Resolve acceptance criteria**, in priority order, and show what was found (confirm with
   the user if ambiguous):
   1. **spec-kit**: grep the branch/ticket slug against `specs/README.md` to find the matching
      `specs/NNN-slug/spec.md`; pull its Success Criteria + Functional Requirements.
   2. **PR body**: `gh pr view <pr> --json body`.
   3. **Linked Jira**: parse a `DS-\d+` ticket key out of the branch name (or PR title), then
      `jira_get_issue` for its description/acceptance criteria.

3. **Resolve the feature's services** (needed for Phase 2, captured now so it doesn't have to
   be re-derived at watch time). Derive candidates from the repo: Helm `values*.yaml` service
   label, the k8s namespace, or the repo name. Confirm or override ONCE with
   `AskUserQuestion` — most repos are a single service, so this is usually a one-click
   confirmation. Persisted below via `state.py init --services`.

4. **Run tests** — this is the "introduced bugs" net. Detect the project's test runner (e.g., in
   a Laravel/review-generator-style repo: `./laravel/core/bin/remotePHP vendor/bin/phpunit`
   against the dev cluster, or the `rg-test` docker image when the cluster is down; other
   stacks differ). **Smoke-test it is alive first** — run one trivial/fast test before the full
   suite. If the smoke test fails (cluster/DB down), **STOP** and ask the user to bring the
   environment up; do not run the full suite blind. Once alive, run the full suite (surfaces
   regressions) plus the feature's own tests. Failures are candidate regressions — carry them
   into the gate in step 6.

5. **Adversarial review = the "worked as intended" + "introduced bugs" check.** Invoke this
   skill's own feature-verification panel via the Workflow tool:
   ```
   Workflow({
     scriptPath: "${CLAUDE_PLUGIN_ROOT}/skills/geiger/workflows/verify-feature.mjs",
     args: { baseBranch: BASE, ticketKey, criteria, diff }
   })
   ```
   Read the result: `{ verdict, confirmed, dismissed }` (`verdict` is `"apto"` or `"no apto"`;
   `confirmed`/`dismissed` are the findings that survived/didn't survive the refutation pass).
   This is a purpose-built panel (not `goat`'s generic `adversarial-review.mjs`): its
   `criteria-coverage` lens walks EACH acceptance criterion and flags an unmet one as HIGH (the
   feature didn't do what it was asked), plus `regression-risk`/`correctness`/`edge-cases`/
   `contract-drift` lenses for bugs the change introduced. Same call/return contract, so the gate
   below is unchanged. `"no apto"` means a criterion was unmet or a real regression survived.

6. **🚦 GATE — present + confirm before posting.** Show the verdict, the test results, and the
   confirmed findings. Ask the user before posting anything to the PR. On OK, check whether the
   anchor actually has an open PR — modes advertise `<pr|branch>`, and a bare branch with no PR
   yet has nowhere to comment on:
   ```bash
   gh pr view <anchor> --json number
   ```
   If that succeeds, post the comment:
   ```bash
   gh pr comment <pr> --body "<summary>"
   ```
   If there is no open PR, print the verdict summary to the user directly instead, and note "no
   PR yet — open one to attach this verdict." The summary should state the verdict, list
   confirmed findings (with fix suggestions), test results, and note that Phase 2 will watch
   production once deployed.

7. **Capture the pre-deploy baseline.** The code is not deployed yet, so the CURRENT production
   error signatures for these services are the Phase 2 "before" set. The changed-file list feeds
   Phase 2's ranking directly, so it must reflect only this branch's changes — diff it against
   the **merge-base** for the same reason as step 1 (a drifted local `$BASE` must not leak
   unrelated files into the ranking). Write the baseline file **atomically**: `prod-delta.py`
   prints `{"error": ...}` to stdout and exits 1 when ES is unreachable, and a plain `>` redirect
   would already have truncated the target, leaving baseline.json holding that error blob (Phase
   2 Boot only checks existence, so it would never re-baseline, and every tick would then die on
   the guarded read):
   ```bash
   python3 $BIN/state.py init --key <key> --services <svc,svc2> \
     --changed-file <(git diff --name-only $(git merge-base "$BASE" HEAD)) --base-branch $BASE

   bp="$(python3 $BIN/state.py baseline-path --key <key>)"
   if python3 $BIN/prod-delta.py "$ES_CREDS" --baseline --services <svc,svc2> > "$bp.tmp"; then
     mv "$bp.tmp" "$bp"
   else
     rm -f "$bp.tmp"
     # ES unreachable: degrade, don't block — warn the user; Phase 2 will baseline at watch start.
   fi
   ```
   This baseline feeds **only the errors lens** — signatures must be deduped across ticks, so they
   need a frozen pre-deploy set. The metric lenses (throughput/latency/cost/saturation/KPI) store
   nothing here: at tick time they compare a pre-deploy ES window (ending at `deploy_at`) against
   the post-deploy window, which also makes them immune to the baseline-contamination trap (a
   Phase-2 run started after deploy still gets a clean pre-deploy window for them).

   Tell the user Phase 2 is armed: **run `/geiger --watch <key>` AFTER deploying.**

---

## Phase 2 — Post-deploy watch loop (softonic ES-specific)

Run by the user after they have deployed — the tool cannot detect a deploy on its own. Mirrors
alert-watcher's self-paced loop, adapted to one feature instead of a channel, and with Jira
triage instead of Slack.

### Boot

**Boot vs. normal tick (decide first, like alert-watcher's A1).** Run:
```bash
python3 $BIN/state.py lock-check --key <key>
```
If `held: true` AND `heartbeat_age_s` is small (< ~1500s), this is a normal tick of an already-running
loop → skip the rest of Boot and jump straight to **Orchestrate (one tick)** below. Otherwise (lock not held, or a stale
heartbeat from a closed session), this is a fresh launch → proceed with Boot:

- **Fresh launch: acquire the lock.**
  ```bash
  python3 $BIN/state.py lock-acquire --key <key>
  ```
  Exit code `2` → another live watcher already holds a fresh lock for this feature → report and **STOP**
  (do not loop). Point the user at `/geiger --stop <key>` if they want to take it over.

- **Record deploy time** as now, unless the user gives an explicit deploy timestamp (pass
  `--deploy-at <ISO>` to `state.py init` if Phase 1's `init` hasn't already run, or re-`init`
  with the real deploy time) — and the watch window: `--window-hours <h>` (default 4). A change
  that ships a scheduled job or a queue consumer needs a window that contains at least one real
  run of it — pass the hours explicitly.

- **Check baseline file.** Existence alone isn't enough — an ES failure during Phase 1's atomic
  write leaves nothing behind (that path is now safe), but an older/hand-created file could still
  be empty or malformed. Validate it: the path from `python3 $BIN/state.py baseline-path --key
  <key>` must exist, parse as JSON, AND have a non-null `signatures` key. If any of that fails
  (missing, unparseable, or no `signatures`), treat it as "no baseline": warn the user this will
  NOT be a true pre-deploy baseline (it may already include the feature's own errors), then
  baseline now — using the same atomic temp-file-then-`mv` pattern as Phase 1 step 7 — into that
  path before ticking.

### Lenses (deployment-aware set)

A regression takes one of four shapes — **error, silence, slowness, cost** — and which shape it
takes depends on what shipped. The original miss this design fixes was a lens that was *never
run*: a config flip (native languages 1→5) crossed a worker timeout, so jobs were killed with no
error log, output silently stopped, and spend spiked — invisible to an error-signature diff. So:

> **Classification only ADDS lenses and orders triage; it never removes a lens.** Run the whole
> cheap set every tick by default. Getting the classification "wrong" must never be able to skip
> the lens that would have caught the regression.

Fan out one sub-agent per lens, in parallel; each returns `{lens, findings: [...], evidence}`.
Derive the change-type from the persisted `changed-file` **paths** (available across sessions,
no diff needed) only to weight ordering and add the KPI lens:
- app/domain code → **errors** first
- `config/*`, Helm `values*.yaml`, env vars → **latency/timeout, throughput, cost** first (behaviour flips emit no error)
- queue/worker config (`horizon.php`, `timeout`, `retry_after`) → **latency/timeout, saturation**
- prompt/model/dependency bumps → **cost, latency, throughput**
- an acceptance criterion naming a measurable output → **add business KPI**

Lens catalogue — all query the same `kubertonic-logs-*` cluster/window `prod-delta.py` uses;
`[deploy_at]` splits the pre- and post-deploy windows (equal duration):

1. **errors** — `prod-delta.py` exactly as today (sub-flow below). Uses the stored baseline.
2. **throughput / success** — per service, completed/succeeded volume pre vs post. Horizon-style
   repos: `DONE` vs `FAIL` counts per consumer; HTTP services: 2xx vs 5xx. Flag a material drop
   (rule of thumb: >30% relative, or success-rate falling). **Catches "output silently stopped."**
3. **latency / timeout** — job/request durations vs the worker/HTTP timeout for that service.
   Flag when p95 climbs toward the timeout, or `count(duration > timeout) > 0` and rising.
   **This lens catches a "N× work in one job vs a fixed timeout" regression directly.**
4. **cost** — model-call volume × duration (token/spend proxy) per service/model, pre vs post.
   If ES lacks spend, flag "investigate spend" when call volume/duration climbs while throughput
   falls, and point at the OpenAI usage dashboard.
5. **saturation** — OOM / `Allowed memory size` / killed signatures, restarts, queue-depth growth.
6. **business KPI** — the feature's own success metric from its acceptance criteria (e.g.
   published-reviews/day). A drop is HIGH ("did what it was asked → then stopped").

Metric lenses need **no stored baseline** — they compare a pre-deploy window (ending at
`deploy_at`) against the post-deploy window at tick time, so baseline contamination can't blind
them. Each metric finding gets a stable synthetic hash `<lens>:<service>[:<detail>]` so it dedups
through the same `jiras` map as an error signature.

### Orchestrate (one tick)

Run the **errors** lens with the existing command, plus the selected metric lenses in parallel:
```bash
python3 $BIN/prod-delta.py "$ES_CREDS" --since <deploy_at> --services <svc,svc2> \
  --baseline-file <baseline-path> --changed-file <changed-file>
```
Collect every lens's findings (error `new` signatures — ranked `likely_this_feature: true` first —
and metric findings). **Partition against the `jiras` suppression map** (`python3 $BIN/state.py
show --key <key>` → `jiras`, hash → Jira key):
- **already-ticketed**: hash is a key in `jiras` — a known regression, still firing.
- **fresh**: hash is not in `jiras` — never triaged for this feature.

Mark the tick `--active` **iff any lens has ≥1 fresh finding** (generalized from "fresh likely
error signature"; still the cheapest check, runs before any JQL/Jira call). This is what lets a
loop where every still-firing regression is already ticketed go quiet — pacing widens and
auto-close eventually fires even though the lenses keep re-reporting the same known findings.
```bash
python3 $BIN/state.py tick --key <key> [--active]
```
Returns `{interval_s, iter_count, quiet_iters}` — the pacing for the next `ScheduleWakeup`
(60s right after activity, widening to 270s then 900s on quiet ticks).

### Triage

**Already-ticketed** findings (hash found in the `jiras` map): skip straight to the status line,
noted as "still firing, tracked in <KEY>" — no JQL search, no dig, no create.

For each **fresh** finding (error signatures ranked `likely_this_feature` first, then metric-lens
findings; up to ~3 in parallel — `coincidental` error signatures are reported but never triaged),
in order — jiras-map check already done above, so the next-cheapest check runs first:

1. **Dedup against existing Jiras by hash via JQL** (reuse alert-watcher's P2c step 1 recipe).
   This catches a ticket filed in a PRIOR session whose `record-jira` call never made it into this
   session's `jiras` map (state reset, or a crash after creating the ticket but before recording
   it). The hash (a deterministic error-signature hash, or the synthetic `<lens>:<service>` hash)
   is embedded as `#<hash>` in created tickets, so:
   ```
   searchJiraIssuesUsingJql
     cloudId: b8a5718d-fb17-46a5-a0d4-91b3c7896de0
     jql: project = DS AND text ~ "#<hash>" AND status NOT IN (Finalizada, Rechazado)
     fields: ["summary","status"]
   ```
   A confirmed hit → note that Jira, do not create another; `record-jira` below and continue.

2. **If no existing Jira: dig the root cause.** For an **error** signature, use its
   `message`/`exception_class` + service + window and trace via x-request-id against the same ES
   cluster `prod-delta.py` used. For a **metric** finding, the evidence *is* the lead: pull the
   before/after numbers for that lens and follow them down — e.g. latency finding → the timeout
   the durations are crossing and the job doing too much per run; throughput drop → what stopped
   completing (killed? never dispatched?); cost → which model/call multiplied.

3. **Create a Bug** (issuetype id `10732`) using the error/alert-watcher recipe verbatim — this is
   still gated so the FIRST creation in a session needs a go-ahead (see below):
   ```
   createJiraIssue
     cloudId: b8a5718d-fb17-46a5-a0d4-91b3c7896de0
     projectKey: DS
     issueTypeName: Bug
     summary: "[Outcome Review] <service>: <short error type OR lens+symptom> (#<hash>)"
     parent: <latest "BAU Maintenance Q{N}.{YY}" epic key>
     additional_fields: { "labels": ["data-watchers"],
                          "customfield_11047": [{"id": "<component id for service>"}] }
     description: (Jira wiki markup) — the feature/PR this regression traces back to, the
       hash (so future recurrences match by `text ~ "#<hash>"`), root cause (for an error: top
       frame / exception class; for a metric finding: the lens + before/after numbers + what they
       point at), sample request-ids where relevant, and 2-4 concrete next steps.
   ```
   Resolve the epic and the component map once per session (same two lookups as
   alert-watcher's Step 4a: latest `BAU Maintenance` epic by `created DESC`; component options
   from the Bug issue type's `customfield_11047.allowedValues`, matched against the service
   name). **The FIRST Jira creation in a session is an outward, permanent action** — show what
   will be created and get a quick go-ahead from the user before that first `createJiraIssue`
   call. Subsequent creations in the same session proceed without re-asking.

4. Record the outcome so re-ticks don't re-triage the same signature:
   ```bash
   python3 $BIN/state.py record-jira --key <key> --hash <hash> --jira <DS-XXXX>
   ```

If a single Jira call fails, log it and continue — never let one failure crash the loop.

### Schedule

```
ScheduleWakeup  delaySeconds: <interval_s>  prompt: "/geiger --watch <key>"  reason: "geiger post-deploy tick"
```
Emit one quiet status line per tick, alert-watcher style — one token per lens that fired, so a
silent/slow/costly regression is visible even when `errors` is clean, e.g.:
```
[tick {iter_count}] errors=0 throughput=-93% latency=54>180s cost=↑ kpi=0 · fresh=2 · next ~{interval_s}s
```

**Auto-close** the watch when either: the window since `started_at` exceeds `window_hours` (from `state.py show`; default 4h), or
activity has been quiet through the widest pacing step for long enough that further ticks are
unlikely to add signal. On close: apply the same PR-existence check as Phase 1 step 6
(`gh pr view <anchor> --json number`) before posting — post the final verdict as a PR comment
(clean run, or the N regressions found with their Jira links) if a PR exists, otherwise print the
final verdict to the user with the same "no PR yet" note. Then:
```bash
python3 $BIN/state.py lock-release --key <key>
```
and stop scheduling further wakeups.

---

## Modes C — `--status` / `--stop`

- `--status <key>`: `python3 $BIN/state.py show --key <key>` → render compactly (services,
  iter_count, current interval, baseline present/absent, Jiras opened this session). Exit; do
  not schedule a wake.
- `--stop <key>`: `python3 $BIN/state.py reset --key <key> --yes` → "Watch stopped, state
  cleared." A loop still scheduled from another session exits cleanly on its next tick
  (`lock-check` → not held). Exit; do not schedule a wake.

## Error handling

- **Test env down** (Phase 1 smoke test fails): stop and ask the user to bring the
  cluster/DB up before running anything further — never proceed blind.
- **ES key/cluster unreachable** (Phase 1 baseline capture, or a Phase 2 tick): report the
  findings without the production delta rather than blocking; don't fail the whole run over a
  transient ES/tunnel issue.
- **A single Jira call fails**: log it and continue triaging the remaining signatures.
- **No acceptance criteria resolvable**: warn the user and fall back to reviewing the diff on
  its own merits (adversarial review still runs; the "worked as intended" check is weaker
  without criteria, but the "introduced bugs" checks are unaffected).
- **A fresh lock is already held for this key**: report and stop — one live watcher per
  feature; point the user at `--stop` if they intend to take it over.

## Files

- `bin/prod-delta.py` — the **errors** lens: ES baseline + delta + signature hash + changed-file
  ranking for the feature's services. The other Phase 2 lenses (throughput/latency/cost/
  saturation/KPI) are instruction-driven ES aggregations run by fanned-out sub-agents — no
  dedicated script, on purpose (keeps the lens set easy to extend without new code).
- `bin/state.py` — per-feature lock, baseline path, and pacing state, keyed by `--key`.
- `workflows/verify-feature.mjs` — this skill's own Phase 1 feature-verification panel
  (criteria-coverage + regression/correctness/edge-case/contract-drift lenses, severity-scaled
  vote). Same call/return contract as `goat`'s `adversarial-review.mjs`, but tuned so an
  unmet acceptance criterion is itself a HIGH ("did not do what it was asked").
