---
name: outcome-review
description: >
  Review the OUTPUTS of a developed feature (a PR/branch): did it work as intended, and did it
  introduce bugs. Phase 1 (pre-merge) runs the project tests + an adversarial review of the diff
  against the feature's acceptance criteria and posts a PR-comment verdict. Phase 2 (post-deploy)
  is a self-paced loop that diffs production error signatures against a pre-deploy baseline for the
  feature's services, ranks each new signature by whether its stack frame hits changed code, and
  triages confirmed regressions to Jira (no Slack). Use when the user says "outcome-review",
  "review the outputs", "did my feature work", "check for regressions", "watch this PR after deploy",
  or "/outcome-review <pr|branch>". Natural continuation of tdd-workflow after it ships a PR.
---

# Outcome Review

Review the **outputs** of one already-developed feature (a PR/branch) — not global telemetry,
not a channel, not an error stream. It answers two questions about that one change:

1. **Did it work as intended?** — an adversarial review of the diff against its acceptance
   criteria, run before merge.
2. **Did it introduce bugs?** — the project's test suite (before merge) and a diff of
   production error signatures against a pre-deploy baseline (after deploy).

It is the natural continuation of the `tdd-workflow` skill: that skill takes a ticket to a
shipped PR; `outcome-review` reviews what that work produced. **Phase 1 is generic** (any
stack, any repo — tests + adversarial review + PR comment). **Phase 2 is softonic-ES-specific**
(kubertonic-logs signatures, Jira triage in project `DS`) and runs only after you deploy.

> All `bin/` scripts referenced below live in this skill's directory. `BIN` stands for
> `${CLAUDE_PLUGIN_ROOT}/skills/outcome-review/bin` — resolve it once at the start of the
> session and invoke the scripts by that absolute path. ES credentials come from the user's
> `$ES_CREDS` environment variable (a `user:password` pair) — pass it as the first argument to
> `prod-delta.py` directly; never prompt the user to paste credentials when it is already set.

## Modes

```
/outcome-review <pr|branch>      # Phase 1: pre-merge review + capture pre-deploy baseline
/outcome-review --watch <pr>     # Phase 2: post-deploy loop (run AFTER you have deployed)
/outcome-review --status <pr>    # print loop state for that feature, exit
/outcome-review --stop <pr>      # release lock, exit the loop
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

5. **Adversarial review = the "worked as intended" check.** Invoke the in-plugin workflow via
   the Workflow tool (same plugin, do not reimplement):
   ```
   Workflow({
     scriptPath: "${CLAUDE_PLUGIN_ROOT}/skills/tdd-workflow/workflows/adversarial-review.mjs",
     args: { baseBranch: BASE, ticketKey, criteria, diff }
   })
   ```
   Read the result: `{ verdict, confirmed, dismissed }` (`verdict` is `"apto"` or `"no apto"`;
   `confirmed`/`dismissed` are the findings that survived/didn't survive the refutation pass).

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
   Tell the user Phase 2 is armed: **run `/outcome-review --watch <key>` AFTER deploying.**

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
loop → skip the rest of Boot and jump straight to **Tick** below. Otherwise (lock not held, or a stale
heartbeat from a closed session), this is a fresh launch → proceed with Boot:

- **Fresh launch: acquire the lock.**
  ```bash
  python3 $BIN/state.py lock-acquire --key <key>
  ```
  Exit code `2` → another live watcher already holds a fresh lock for this feature → report and **STOP**
  (do not loop). Point the user at `/outcome-review --stop <key>` if they want to take it over.

- **Record deploy time** as now, unless the user gives an explicit deploy timestamp (pass
  `--deploy-at <ISO>` to `state.py init` if Phase 1's `init` hasn't already run, or re-`init`
  with the real deploy time).

- **Check baseline file.** Existence alone isn't enough — an ES failure during Phase 1's atomic
  write leaves nothing behind (that path is now safe), but an older/hand-created file could still
  be empty or malformed. Validate it: the path from `python3 $BIN/state.py baseline-path --key
  <key>` must exist, parse as JSON, AND have a non-null `signatures` key. If any of that fails
  (missing, unparseable, or no `signatures`), treat it as "no baseline": warn the user this will
  NOT be a true pre-deploy baseline (it may already include the feature's own errors), then
  baseline now — using the same atomic temp-file-then-`mv` pattern as Phase 1 step 7 — into that
  path before ticking.

### Tick

```bash
python3 $BIN/prod-delta.py "$ES_CREDS" --since <deploy_at> --services <svc,svc2> \
  --baseline-file <baseline-path> --changed-file <changed-file>
```
Read `new` (signatures absent from the baseline, ranked — `likely_this_feature: true` items
first), `new_count`, `likely_count`.

**Partition against the `jiras` suppression map before deciding activity or triaging.** Read
`python3 $BIN/state.py show --key <key>` and take its `jiras` object (hash → Jira key), populated
by every prior `record-jira` call for this feature. Split the `likely_this_feature` signatures in
`new` into:
- **already-ticketed**: hash is a key in `jiras` — a known regression, still firing.
- **fresh**: hash is not in `jiras` — never triaged for this feature.

Mark the tick `--active` **iff there is at least one fresh likely signature** — not merely "any
likely signature at all". This is the cheapest check and runs first (before any JQL/Jira call).
It's what lets a loop where every still-firing regression is already ticketed go quiet: pacing
widens on quiet ticks and auto-close eventually fires, even though `prod-delta` keeps reporting
the same known signature on every poll (it's still absent from the baseline).
```bash
python3 $BIN/state.py tick --key <key> [--active]
```
This returns `{interval_s, iter_count, quiet_iters}` — the pacing for the next `ScheduleWakeup`
(60s right after activity, widening to 270s then 900s on quiet ticks).

### Triage

**Already-ticketed** likely signatures (hash found in the `jiras` map): skip straight to the
status line, noted as "still firing, tracked in <KEY>" — no JQL search, no dig, no create. They
were already handled by a prior tick.

For each **fresh** likely signature (up to ~3 in parallel — `coincidental` signatures are
reported in the status line but never triaged, ticketed or not), in order — jiras-map check
already done above, so the next-cheapest check runs first:

1. **Dedup against existing Jiras by signature hash via JQL** (reuse alert-watcher's P2c step 1
   recipe). This catches a ticket filed in a PRIOR session whose `record-jira` call never made it
   into this session's `jiras` map (e.g. state was reset, or a session crashed after creating the
   ticket but before recording it): `signature_hash` is a deterministic 12-char hash; created
   tickets embed it as `#<hash>` in the summary, so:
   ```
   searchJiraIssuesUsingJql
     cloudId: b8a5718d-fb17-46a5-a0d4-91b3c7896de0
     jql: project = DS AND text ~ "#<hash>" AND status NOT IN (Finalizada, Rechazado)
     fields: ["summary","status"]
   ```
   A confirmed hit → note that Jira, do not create another; `record-jira` below and continue.

2. **If no existing Jira: dig the root cause.** Use the signature's `message`/`exception_class`
   and the service + window to trace the underlying failure (x-request-id tracing against the
   same ES cluster `prod-delta.py` used).

3. **Create a Bug** (issuetype id `10732`) using the error/alert-watcher recipe verbatim — this is
   still gated so the FIRST creation in a session needs a go-ahead (see below):
   ```
   createJiraIssue
     cloudId: b8a5718d-fb17-46a5-a0d4-91b3c7896de0
     projectKey: DS
     issueTypeName: Bug
     summary: "[Outcome Review] <service>: <short error type> (#<hash>)"
     parent: <latest "BAU Maintenance Q{N}.{YY}" epic key>
     additional_fields: { "labels": ["data-watchers"],
                          "customfield_11047": [{"id": "<component id for service>"}] }
     description: (Jira wiki markup) — the feature/PR this regression traces back to, the
       signature hash (so future recurrences match by `text ~ "#<hash>"`), root cause (top
       frame / exception class), sample request-ids, and 2-4 concrete next steps.
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
ScheduleWakeup  delaySeconds: <interval_s>  prompt: "/outcome-review --watch <key>"  reason: "outcome-review post-deploy tick"
```
Emit one quiet status line per tick, alert-watcher style, e.g.:
```
[tick {iter_count}] new={new_count} likely={likely_count} · next ~{interval_s}s
```

**Auto-close** the watch when either: the window since `started_at` exceeds the default 4h, or
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

- `bin/prod-delta.py` — ES baseline + delta + signature hash + changed-file ranking for the
  feature's services.
- `bin/state.py` — per-feature lock, baseline path, and pacing state, keyed by `--key`.
- `../tdd-workflow/workflows/adversarial-review.mjs` — reused in-plugin for the Phase 1
  adversarial review; not reimplemented here.
