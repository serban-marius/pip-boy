# Design — `outcome-review` skill (tdd-workflow plugin)

**Date:** 2026-07-08
**Plugin:** `tdd-workflow` (adds a second skill, `outcome-review`)
**Status:** approved design, pre-implementation

## Purpose

Review the **outputs of a developed feature** — not global telemetry, one specific
change. Answer two questions about a single PR/branch:

1. **Did it work as intended?** (does the change actually satisfy its acceptance criteria)
2. **Did it introduce bugs?** (regressions in existing behavior; new production errors)

It is the natural continuation of the `tdd-workflow` skill: that skill takes a ticket to a
shipped PR (Steps 1–7); `outcome-review` reviews what that work produced, first statically
before merge, then against production after deploy. It is a **reviewer of outputs**, not a
watcher — it is scoped to one feature, not a channel or an error stream.

## Why it lives in `tdd-workflow` (not a new plugin)

- It is the post-ship phase of the same pipeline; conceptually one plugin.
- Phase 1 reuses tdd-workflow's own `workflows/adversarial-review.mjs` **in-plugin**
  (`${CLAUDE_PLUGIN_ROOT}` resolves it) — no fragile cross-plugin cache paths.
- tdd-workflow already bakes in softonic conventions (Jira cloud ID, `DS` project,
  `softonic-development/<service>` repos, `gh` CLI in Step 7). Phase 2's softonic-ES
  telemetry check is therefore *in keeping* with the plugin: **Phase 1 stays fully
  stack-agnostic; Phase 2 is the softonic-specific bit.**

## Decisions locked during brainstorming

| Decision | Choice |
| --- | --- |
| Scope | Bridge: pre-merge static gate **and** post-deploy production check, one spec |
| Input anchor | **PR / branch** — derive diff + touched services from git; criteria from linked spec/Jira |
| Prod correlation | **Layered** — baseline-delta net, then rank each new signature by whether its stack frame hits changed code |
| Post-deploy watch model | **Self-paced loop** over a bounded window (alert-watcher style) |
| Outputs | Report + **PR comment** + **Jira triage** for confirmed post-deploy regressions. **No Slack.** |
| Packaging | New skill inside `tdd-workflow` (option C); minor version bump |

## Invocation modes

Mirrors alert-watcher's mode block. Every mode is keyed by the PR/branch so the two phases
bridge through one state file.

```
/outcome-review <pr|branch>      # Phase 1: pre-merge review + capture pre-deploy baseline
/outcome-review --watch <pr>     # Phase 2: post-deploy loop (run AFTER you have deployed)
/outcome-review --status <pr>    # print loop state for that feature, exit
/outcome-review --stop <pr>      # release lock, exit the loop
```

State file (per PR/branch) holds: resolved acceptance criteria, touched services,
changed-file list, pre-deploy baseline signatures, watch-start, pacing, lock heartbeat,
and any Jira keys opened this session.

## Phase 1 — Pre-merge review (generic, no production)

1. **Resolve the feature.** Capture `<BASE_BRANCH>` (`git symbolic-ref refs/remotes/origin/HEAD`,
   fallback to the fork point — never assume `main`) and the diff. Resolve acceptance
   criteria in priority order:
   1. spec-kit `specs/NNN/spec.md` if the branch maps to one (Success Criteria + FRs),
   2. the PR body,
   3. the linked Jira issue (parse `DS-xxxx` from the branch/PR name, `jira_get_issue`).

   Show what was found; if ambiguous, confirm with the user before proceeding.

   **Resolve the feature's services** (needed for Phase 2): derive candidates from the repo —
   Helm/k8s config (namespace, service label) or the repo name — and confirm/override with the
   user once (`AskUserQuestion`), then persist to state. Most repos are a single service (e.g.
   review-generator); the confirm step handles the multi-service case without guessing.
2. **Run tests = the "introduced bugs" net.** Detect the runner (this ecosystem: Laravel /
   phpunit via the `rg-test` docker image or `remotePHP`), **smoke-test it is alive first**,
   then run the **full suite** (surfaces regressions) plus the feature's own tests. Failing
   tests are candidate regressions.
3. **Adversarial review = the "worked as intended" check.** Capture the diff **once** and
   delegate to the in-plugin `workflows/adversarial-review.mjs`
   (`{ baseBranch, ticketKey, criteria, diff }` → `{ verdict, confirmed, dismissed }`). Its
   lenses already probe "which acceptance criterion has NO test." No new workflow needed.
4. **🚦 GATE — present + confirm.** Show the verdict, test results, and confirmed findings.
   Ask before posting the **PR comment** with the summary. Then capture the **pre-deploy
   baseline**: `prod-delta.py --baseline` snapshots the feature's services' *current*
   production error signatures into state — the code is not deployed yet, so these are the
   "before" set for Phase 2.

## Phase 2 — Post-deploy watch (softonic ES-specific, self-paced loop)

Run by the user **after they have deployed** (the tool cannot detect deploy on its own). If
Phase 1 never ran, baseline at watch-start and warn that it is not a true pre-deploy baseline.

1. **Boot** like alert-watcher: take a per-PR lock, record watch-start, schedule ticks over a
   bounded window (default ~4h; pacing widens 60s → 270s → 900s), then `ScheduleWakeup`.
2. **Each tick:** `prod-delta.py --since <deploy> --services <...>` fetches current signatures
   for the feature's services and **set-diffs against the baseline** by signature hash →
   *new* signatures only.
3. **Layered ranking:** for each new signature, check whether its top app frame (`top_frame`
   file) is in the changed-file list → tag `likely-this-feature` vs `coincidental`.
4. **Triage (no Slack):** for confirmed `likely-this-feature` regressions — dig the root cause
   (x-request-id trace), dedup against **open** `DS` Jiras by signature hash (`text ~ "#<hash>"`),
   and open/link a Jira bug (BAU Maintenance epic, service→component map, `#<hash>` in the
   summary), reusing the error/alert-watcher recipe. The **first** Jira creation in a session
   gets a go-ahead prompt (outward, permanent action).
5. **Auto-close** after the window: post a final post-deploy verdict to the PR comment (clean,
   or N regressions with Jira links) and release the lock.

## Correlation detail — signatures and ranking

- **Signature hash:** deterministic 12-char SHA1 over (normalized message, exception class,
  top app frame) — the same recurrence key alert-watcher uses, so a regression that recurs
  hashes the same across runs and dedups against an existing Jira.
- **Baseline delta:** `new = signatures(after) − signatures(baseline)` by hash. Catches
  everything genuinely new in the feature's services (few false negatives).
- **Changed-file ranking:** `top_frame` file ∈ changed files → `likely-this-feature`; else
  `coincidental`. Precision without dropping coverage — coincidental items are still reported,
  just ranked lower and not auto-triaged.

## Components

New (everything else is reuse):

| File | Job |
| --- | --- |
| `skills/outcome-review/SKILL.md` | Orchestrator: modes, both phases, gates, triage recipe |
| `skills/outcome-review/bin/prod-delta.py` | ES baseline + delta + signature hash + changed-file ranking (~200 lines; borrows error-watcher's ES-connection pattern) |
| `skills/outcome-review/bin/state.py` | Per-PR lock + baseline persistence + pacing (light adaptation of alert-watcher's `state.py`) |

Reused as-is:

- `workflows/adversarial-review.mjs` — Phase 1 review panel (already in the plugin).
- Jira-triage recipe (BAU epic, component map, hash dedup) — inline prose in the SKILL,
  copied from error/alert-watcher's proven steps.
- Loop / `ScheduleWakeup` / pacing mechanics — the alert-watcher pattern.

## Error handling

- **Test env down:** stop and ask the user to bring it up before writing tests/running —
  never proceed blind (same as tdd-workflow Step 0).
- **ES key expiry / unreachable:** post findings without the prod delta rather than blocking;
  ask for a fresh key, then continue.
- **Single Jira call fails:** log and continue; never crash the loop.
- **No criteria resolvable:** warn and fall back to reviewing the diff on its own merits.
- **Lock held by a live loop for the same PR:** report and stop (single-instance per feature).

## Testing

Ponytail rule — one runnable check per non-trivial script, no framework:

- `prod-delta.py --selftest`: asserts the signature set-diff and the changed-file ranking
  (a signature whose `top_frame` hits a changed file is `likely-this-feature`; one that does
  not is `coincidental`; a signature present in the baseline is never reported).
- `state.py --selftest`: asserts lock acquire/heartbeat/release and the pacing transitions
  (60s → 270s → 900s).

## Packaging & versioning

- Add under `development/common/plugins/tdd-workflow/skills/outcome-review/`.
- Bump `tdd-workflow` **1.0.0 → 1.1.0** (new skill = minor) in **both**
  `.claude-plugin/plugin.json` and the marketplace's `.claude-plugin/marketplace.json`
  (both must match — mandatory per the marketplace CLAUDE.md).
- Update the tdd-workflow plugin `description` and `README.md` to mention the
  post-implementation review skill.
- Work happens in the `softonic-development-ai-plugins` marketplace repo (branch
  `feat/tdd-workflow-outcome-review`), **not** review-generator.

## Explicitly out of scope (YAGNI)

- **No Slack** (user decision).
- **No automatic deploy detection** — Phase 2 is user-triggered.
- **No new review workflow** — Phase 1 reuses `adversarial-review.mjs` unchanged. A dedicated
  "criteria-coverage" lens can be added later if the existing lenses prove insufficient.
- **No multi-repo fan-out** — one feature = one PR in one service repo.
