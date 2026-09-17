---
name: goat
description: Take a JIRA task from ticket to PR with a team of specialized agents, in TDD and with human brakes. Pipeline - Spec (PM/Spec-Driven) -> Architect -> Failing tests (TDD) -> Implementation to green -> Independent reviewer -> commit/PR. Hybrid model- the skill keeps the two human gates (after the spec and before the commit) and delegates the parallelizable steps to .mjs workflows (spec-explore: exploration fan-out; architect-panel: design judge-panel; adversarial-review: multi-lens panel + vote). Stack-agnostic (detects the project). If the repo uses spec-kit (specs/ + .specify/), persists the spec as a versioned artifact (spec.md/research.md/checklists); if not, it asks. Triggers- "/goat PROJ-123", "implement ticket X with agents", "take this jira task and build it with TDD", "from jira to PR with agents", "goat", "jira-tdd". Spanish triggers also- "implementa el ticket X con agentes", "coge esta tarea de jira y móntala con TDD", "de jira a PR con agentes".
---

# goat · from a JIRA ticket to a PR, with a team of agents

Orchestrate a team of specialized agents to implement a JIRA task following TDD,
**with two human gates**. You are the team's architect, not the glue.

## Philosophy (do not break it)

- **Glue rule:** every role exists because it sees something the previous one can't. Don't add decorative agents.
- **The validator is INDEPENDENT:** the reviewer did not write the code. "An agent that reviews itself, doesn't review."
- **Real TDD:** tests are written FIRST, seen RED, and only then is code implemented to GREEN.
- **Brakes on real code:** you do NOT go ticket-to-PR on autopilot. You stop after the spec and before the commit.

## The argument

`$ARGUMENTS` = the ticket key (e.g. `PROJ-123`), optionally preceded by `--auto` (see **`--auto` mode**
at the end: the human gates become automated checks and the run ends with a `GOAT RESULT:`
line). If the key is absent, ask for it — unless `--auto`, in which case print
`GOAT RESULT: blocked needs-decision: no ticket key` and stop.

## Prerequisites (required)

- **JIRA MCP** — to fetch the ticket AND its attachments in Step 1 (`mcp__atlassian-local__jira_get_issue` / `jira_search` / `jira_download_attachments`). If it's not available, ask the user to paste the ticket text *and* upload any screenshots, and continue.
- **context7** — the architect panel's docs-backed reasoning and any library/stdlib verification lean on it. Load its tools via ToolSearch (`select:mcp__context7__resolve-library-id,mcp__context7__query-docs`).
- **ponytail** — the architect panel's YAGNI/minimal-design lens assumes ponytail's laziness ladder is in effect (does this need to exist? does the stdlib do it? one line?).
- **`Workflow` tool** — for the fan-out steps (Steps 2, 3, 6). Without it, each falls back to a single subagent (noted per step).

---

## Step 0 · git safety + repo context

1. Check the tree is clean (`git status`). If there are uncommitted changes, **stop** and warn.
2. Detect the stack to know the test command (don't assume):
   - PHP/Laravel → `composer`/`phpunit` or `php artisan test` (+ `duster`, `phpmd` if present).
   - Node → `test` script in `package.json` (jest/vitest).
   - Python → `pytest`.
   - Other → find the runner; if you can't, ask.
   - **Smoke-test the runner BEFORE continuing:** knowing the command isn't enough; confirm it can RUN. Run something trivial (a small existing test, `--version`, or the runner empty). If the test environment isn't alive (DB down, k8s/Docker cluster not up, container stopped), **stop and ask the user to bring it up NOW** — don't discover it mid-Step 4, after you've written the tests and can't see red. Heavy environments (KIND/k8s, sail/docker, remote DB) are the #1 cause of late blocking. (`--auto`: see the mode table.)
3. **Capture the base branch, then create the work branch.** Don't assume `main` — many repos (e.g. Laravel/`develop`, `master`) fork elsewhere. Record the branch you're forking from (`git rev-parse --abbrev-ref HEAD`, or the remote default via `git symbolic-ref refs/remotes/origin/HEAD`); call it `<BASE_BRANCH>`. Then `git checkout -b feat/<PROJ-123>-<short-slug>`. Pass `<BASE_BRANCH>` to every `git diff` and to the reviewer workflow below — `main` is only a fallback.
4. **Detect spec-kit**: does the repo have `specs/` and/or `.specify/`? If **yes**, this pipeline persists the spec artifacts (see Step 2.5). If **no**, do NOT assume: ask the user *"this repo doesn't use spec-kit — should I just generate the spec in chat (as usual) or do you want to adopt it?"* and respect the answer. Check whether `scripts/check-specs.sh` exists for validation. (`--auto`: see the mode table.)

## Step 1 · 📋 Fetch the JIRA ticket

Use the Atlassian MCP: `mcp__atlassian-local__jira_get_issue` with the key (pass
`fields: "*all"` and `comment_limit` high enough to see the discussion). If it doesn't resolve,
search with `mcp__atlassian-local__jira_search`. Extract: title, description, acceptance criteria,
relevant comments, attachments/links.

**Download and READ the attachments — the ticket text is NOT the whole ticket.** Bug reports
routinely put the actual error in a *screenshot* (a stack trace, a failing query, a red UI, a log
line) and leave the description as one vague sentence. A text-only read of such a ticket sends the
whole pipeline off to solve the wrong problem — and nothing downstream will catch it, because the
spec, tests, and review all inherit that blind starting point. So:

1. `mcp__atlassian-local__jira_download_attachments` with `target_dir` = a scratch dir
   (e.g. the session scratchpad). This pulls images, PDFs, logs, etc.
2. `Read` every downloaded image/PDF — the Read tool interprets images, so screenshots become
   text you can actually use. Transcribe the meaningful content (error messages, query, values).
3. If an attachment is unreadable or ambiguous, say so and ask the user rather than guessing. (`--auto`: see the mode table.)

Summarize the ticket in 3-4 lines, **folding in what the attachments revealed** (often the real
crux). Carry this combined text forward — it is what you pass as `args.ticket` in Step 2.

**Triage the ticket size NOW — it decides how much fleet the rest of the pipeline spends:**

- **Trivial** (typo, config value, one obvious guard, doc change): do NOT use the workflows at
  all — run the whole pipeline in classic mode (single subagents, see each step's fallback), or
  tell the user this ticket doesn't need the skill.
- **Small** (bugfix or contained change, likely 1-3 files): use the workflows but with the
  reduced fan-outs — pass `angles: ["entrypoints", "precedent", "tests"]` in Step 2; the review
  panel auto-shrinks on a small diff.
- **Feature / cross-cutting**: full fan-outs (all angles, all lenses).

**Also detect multi-repo scope NOW.** If the ticket needs changes in MORE than one repo (e.g. an
API change plus its consumer), the spec at Gate 1 must include a **delivery plan**: which repos,
one PR per repo, which PR depends on which, and — critically — the **contract between them** (the
API shape, event schema, package version… whatever the dependent PR builds against). The pipeline
below then runs **once per repo, in dependency order**, with a gate between PRs (see Step 8).

## Step 2 · 🧭 SPEC (parallel exploration workflow)

Instead of a single subagent, launch the **workflow** `spec-explore` — it fans out read-only
explorers across distinct angles (entrypoints, domain, precedent, tests, constraints) and
synthesizes a spec draft from evidence-backed findings. More coverage than a single sequential
exploration.

Invoke it with the `Workflow` tool, passing the skill's script and the ticket:

```
Workflow({
  scriptPath: "<BASE>/workflows/spec-explore.mjs",
  args: { ticket: "<ticket text>", hints: ["<optional hint>", ...], angles: ["<optional subset>", ...] }
})
```

where `<BASE>` is the "Base directory for this skill" shown when it's invoked. Returns
`{ spec, facts }`: `spec` carries summary, chokePoint, acceptanceCriteria, edgeCases, openQuestions.

`angles` (optional) picks a subset of the six exploration angles (`entrypoints`, `domain`,
`precedent`, `tests`, `constraints`, `side-effects`) — pass 3 for a small ticket per the Step 1
triage, omit it for a feature.

**Pass `args` as a real JSON object, never a JSON-encoded string.** The workflow reads
`args.ticket`; if no ticket text reaches it, it **aborts** and returns
`{ spec: null, error }` instead of exploring blind — re-run it with `args.ticket` populated. Include
the attachment content from Step 1 inside `args.ticket`. After the workflow returns, sanity-check
the spec against the ticket before Gate 1: **the ticket is the source of truth, not the branch
name** (which may be leftover from previous work). If the spec's summary doesn't match what the
ticket (and its screenshots) actually describe, the ticket didn't reach the explorers — re-run with
`args.ticket` correctly populated instead of presenting a spec you know is off-topic.

(If the `Workflow` tool isn't available in the environment, fall back to classic mode: a
general-purpose `Agent` subagent with the same brief — summary, verifiable criteria, edge cases,
open questions — exploring the code before writing.)

### 🚦 GATE 1 — present the spec and STOP
Show the spec + criteria + assumptions to the user — **including the delivery plan if the ticket
spans repos** (repos, PR order, the contract between PRs). Ask: **"Do I approve this spec or adjust something?"**
**End the turn and wait for their answer.** Don't proceed without an explicit OK. Incorporate their changes if asked. (`--auto`: see the mode table.)

## Step 2.5 · 📄 Persist the spec artifact (only if the repo uses spec-kit)

(After the Gate 1 OK, and only if you detected spec-kit in Step 0 — or the user agreed to adopt it.)
Write the approved spec as a versioned artifact under `specs/NNN-<slug>/`:

- `spec.md` — **implementation-agnostic**: user scenarios (Given/When/Then), Functional Requirements
  (FR-001…), Success Criteria, Edge Cases, Clarifications, **Known Defects**. NO paths/classes/`PR #N`.
- (the other two files are filled in by the Architect and the Test-author, see Steps 3 and 4.)

Use the `.specify/templates/spec-template.md` template if it exists. Number with the next free `NNN` and
add a row to `specs/README.md`. If `scripts/check-specs.sh` exists, run it and leave the spec green.

If the repo does **not** use spec-kit, skip this step (the spec lives in chat + PR body, as usual).

## Step 3 · 🏛️ ARCHITECT (workflow: design judge-panel)

(After the spec is approved.) Instead of a single architect, launch the **workflow**
`architect-panel` — 3 independent architects design the change in parallel through distinct lenses
(convention-first, risk-first, yagni), then a synthesizer reconciles them into ONE plan. Design
space is wide; a panel beats one attempt at catching the layering/blast-radius/over-engineering an
individual would miss. Invoke it with the `Workflow` tool:

```
Workflow({
  scriptPath: "<BASE>/workflows/architect-panel.mjs",
  args: { spec: <approved spec object or text>, ticketKey: "<PROJ-123>", facts: "<facts from Step 2>", hints: ["<optional hint>", ...] }
})
```

**Always pass `facts`** — the `facts` string returned by spec-explore in Step 2. It's the
evidence-backed repo map you already paid for; with it, the 3 architects verify against grounded
findings instead of each re-exploring the whole repo from scratch (that re-exploration was a big
chunk of the quota).

Returns `{ plan, designs }`: `plan` carries chosenApproach, rationale (what it took/discarded from
each lens), files (path + change), contracts, order, risks.

(If `Workflow` isn't available, fall back to classic mode — a single subagent: *"You are the
ARCHITECT agent. Given this approved spec and the repo code, design WHERE and HOW it fits: files
created/touched, layers, contracts, dependencies. Respect existing conventions (look first). Do NOT
implement: deliver the PLAN — files + what each change does + recommended order + risks."*)

Show the plan in 5-6 lines (not a gate; it's so the user sees it go by). If the plan reveals
the spec was wrong, go back to Gate 1. (`--auto`: see the mode table.)

**Spec-kit**: if the repo uses it, dump the plan's evidence (paths, classes, contracts, risks, links
to Jira/PR) into `specs/NNN-<slug>/research.md` — implementation details that `spec.md` does NOT carry go here.

## Step 4 · 🔴 TEST-AUTHOR agent (failing tests)

Launch an independent subagent (does not implement):

> You are the TEST-AUTHOR agent. Write the tests that verify the spec's ACCEPTANCE CRITERIA,
> following AAA and the project's framework. One test per criterion + edge cases. Do NOT write the
> implementation; the tests must FAIL because the functionality doesn't exist yet. Write the test files.
>
> Test the BEHAVIOUR each criterion promises, not a structural proxy for it. When a criterion is a
> guarantee about what happens under stress — resilience, independence, partial success, "one X
> failing/timing out must not affect Y", "each unit is isolated" — the test MUST drive that exact
> scenario: force one unit to fail and assert the others still succeed. Asserting the structure that
> *should* produce the guarantee (dispatch counts, config values, wiring, a single unit's happy path)
> does NOT verify it — that is precisely the gap that lets the original bug ship again.

Then **run the test command and CONFIRM they are RED — and red for the RIGHT reason.** If they pass
green without implementation, something is wrong (a test that proves nothing) → fix it. (`--auto`: see the mode table.) Beware the
structural test for a behavioural criterion: it can be RED for the wrong reason (a missing method, not
the missing guarantee) and still prove nothing once green — check each test actually pins its
criterion's behaviour. If the headline criterion is a behavioural guarantee and no test drives it,
the suite is incomplete no matter how green it is. Show the red. *"A test that can't fail proves nothing."*

**Spec-kit**: if the repo uses it, fill `specs/NNN-<slug>/checklists/requirements.md` — a spec-quality
checklist (completeness/clarity/consistency) mapping each criterion to its FR. Commit the 3
spec files alongside the feature (or as a spec commit) in Step 7.

## Step 5 · 🟢 Implementation (YOU do it, the main loop)

Implement following the architect's PLAN, the minimum to turn the tests GREEN. Iterate:
implement → run tests → adjust, until all pass. Respect conventions and, if present,
run the stack's linter/formatter (scoped — see below). Do NOT touch the tests to make them pass (except a genuine test bug).

**Keep the formatter on a leash.** Run it scoped to the files you changed and diff-check before you
stage. An auto-formatter (or a mis-versioned/buggy one) that rewrites files OUTSIDE your change is
misfiring — do NOT commit that churn: it buries your real diff in the review and can touch
vendored/base files the repo forbids editing. Revert the unrelated reformatting, match the
surrounding style by hand, and confirm the diff is only the files your change actually touches.
If the committed style and the formatter disagree on files you didn't write, trust the committed
style — a formatter fighting the whole repo is the tool misbehaving, not the codebase.

**If the change adds or modifies a DB query, prove it's efficient with `EXPLAIN`.** Now that the
query is agent-written, "the tests pass" only means it's *correct*, not that it *scales* — a query
that full-scans a 20M-row table passes every test on an empty dev DB and then melts production.
Run `EXPLAIN` against the dev DB for each new/changed query — every SQL database supports it
(`EXPLAIN <sql>` through whatever runner the project uses), and most ORMs expose it on the query
builder (e.g. Laravel's `->explain()`) — and check the plan:

- Is it hitting an **index**, or is it a full table scan (`type: ALL` in MySQL, `Seq Scan` in
  Postgres)?
- Does an index it needs actually **exist** on that column? If the query filters/sorts on a column
  with no index (a common trap on `created_at`, status flags, and FKs referenced by
  relationship/`EXISTS` subqueries), flag it: either add the index in this change or call it out
  as a follow-up with the row-count context.
- Watch for filesorts/temporary tables and correlated subqueries evaluated per row.

For non-SQL stores, use the equivalent plan/profiling tool (e.g. MongoDB's `.explain()`) with the
same questions: index vs full scan, and does the index exist.

Report the plan (and any index gap) at Gate 2 so the reviewer sees the performance profile, not
just the diff. Note whether the concern is a regression this PR introduces or pre-existing.

## Step 6 · ✅ REVIEWER (workflow: adversarial multi-lens panel)

Instead of a single reviewer, launch the **workflow** `adversarial-review` — a panel of independent
reviewers, each with a distinct lens (correctness, edge-cases, security, conventions,
test-quality), then **severity-scaled verification**: `high` findings go through 3 skeptics that
try to REFUTE (survives if <2 refute), `medium` through 1, and `low` are reported without a panel.
Kills the plausible-but-false findings a single reviewer lets through. None of these agents saw how
you implemented it (real independence).

Capture the diff ONCE and pass it via `args.diff` — so the ~10-40 panel agents don't each re-run
`git diff` (that was the bulk of the quota). Invoke it with the `Workflow` tool:

```
# first, in the repo: git --no-pager diff <BASE_BRANCH>   -> save the output as <DIFF>
Workflow({
  scriptPath: "<BASE>/workflows/adversarial-review.mjs",
  args: { baseBranch: "<BASE_BRANCH>", ticketKey: "<PROJ-123>", criteria: "<acceptance criteria>", diff: "<DIFF>" }
})
```

Returns `{ verdict: "apto"|"no apto", confirmed: [...], dismissed: [...] }`. The verdict is
"no apto" if any high-severity finding survives.

(If `Workflow` isn't available, fall back to classic mode: an independent `Agent` subagent that
receives the `git diff` + the criteria and returns findings by severity and a verdict.)

Apply the confirmed high-severity findings (go back to Step 5 if needed) and report the rest.

### 🚦 GATE 2 — present the diff + review and STOP
Show: change summary, tests green, reviewer findings, and (if the change touches a query) the
`EXPLAIN` plan + any index gap from Step 5. Ask:
**"Do I commit and open the PR, or adjust something?"** **End the turn and wait for the OK.** (`--auto`: see the mode table.)

## Step 7 · 🚀 Commit + PR (after the OK)

- If the project is Laravel and the `laravel-workflow:ship` skill exists, **delegate to it** (commit + duster + PR). (`--auto`: see the mode table.)
- Otherwise: commit with a message referencing the ticket (`PROJ-123: <title>`), push, and `gh pr create`
  with body = spec + what was done + how it was validated + open reviewer findings. Link the JIRA ticket.

## Step 8 · 🚦 GATE 3 — between PRs (only for multi-repo tickets)

(Only when the Gate 1 delivery plan has more PRs pending.) An open PR is **open business** — do
NOT march to the next repo while feedback on the previous one goes unread. Before starting the
next repo's pipeline:

1. Check the PR you just opened for review feedback: `gh pr view <n> --comments` (and CI status).
2. Present what you found and **STOP**: *"PR N has X review comments / CI status Y — do I address
   them now, or proceed to the next repo's PR?"* **End the turn and wait.** Warn that
   contract-level feedback (anything changing the API shape / schema / version the next PR builds
   against) would force rework if we proceed — addressing that first is almost always right. (`--auto`: see the mode table.)
3. Addressing feedback is a normal edit → test → adjust loop on the existing branch (back to
   Step 5; re-run Step 6 if the change is substantial), then push.
4. When the user says proceed: start the next repo's pipeline **from Step 0 in that repo**,
   carrying the approved spec's delivery plan and the agreed contract into `args.ticket` — the
   dependent PR builds against the contract, not against an unmerged branch's implementation
   details.

## `--auto` mode (unattended; what sprint-autopilot's workers run)

Without `--auto` nothing in this skill changes. With it, every point where the interactive run asks or
stops takes the conservative automated path below.

The run ends with exactly one line:

- `GOAT RESULT: pr-open <url> [<url>…] [ac:<id>[,<id>…]] [needs-repo:<repo>:<why>]`
- `GOAT RESULT: blocked <code>: <reason>`

When the task spec names acceptance-criterion ids (`AC1`, `AC2`…), `ac:` lists the ones this PR actually
covers — the ids whose criterion the diff satisfies, not the ids you were handed. If the spec work shows a
criterion lands in a repo you were not given, say so with `needs-repo:<repo>:<why>` rather than shipping
around it or calling the ticket done: reporting the gap is the successful outcome there.

Before printing a `blocked` line, push the branch as it is (`git push -u origin <branch>`) so a human can
resume from exactly where you stopped — **except** on `secret-in-diff`, where nothing is pushed.

| Point | Interactive | `--auto` |
|-------|-------------|----------|
| Step 0 test env down | ask | `blocked test-env-down` |
| Step 0 no spec-kit | ask to adopt | don't adopt; the spec goes in the PR body |
| Step 1 unreadable attachment | ask | `blocked unreadable-attachment` |
| **Gate 1** | STOP | self-check: `spec.summary` matches the ticket (and its attachments) and `openQuestions` is empty or holds only questions the explorers answered from code. A product question left → `blocked needs-decision: <questions>` |
| Step 3 plan contradicts spec | back to Gate 1 | `blocked spec-plan-mismatch` |
| Step 4 tests won't go RED | fix and continue | same, 2 attempts, then `blocked tests-not-red` |
| **Gate 2** | STOP | require `verdict: apto`; apply confirmed high findings and re-review; 2 cycles max → `blocked review-not-apto: <findings>` |
| Step 7 | `ship` if Laravel | `ship --auto` if Laravel, then translate its last `SHIP RESULT: pr-open …` / `SHIP RESULT: blocked …` line into your own final `GOAT RESULT: pr-open …` / `GOAT RESULT: blocked …` line, appending your own `ac:` / `needs-repo:` (same PR payload, outer marker — the coordinator only reads the outer one); otherwise `gh pr create` **ready for review** (not draft), body = spec + EXPLAIN + open findings |
| **Gate 3** multi-repo | STOP between PRs | proceed to the next repo; feedback on the open PR is handled by whoever runs the merge watch |
| Any question a human would answer | ask | decide conservatively from the code, or `blocked needs-decision` |

Blocked codes are the ones sprint-autopilot's `references/conventions.md` lists; use them verbatim.

---

## Notes

- **Hybrid model (skill + workflows):** the SKILL keeps the human gates (Gate 1 after the
  spec, Gate 2 before each commit, Gate 3 between PRs on multi-repo tickets) — that's
  non-negotiable and why this stays a skill, not a
  single workflow that would run to the end without stopping. The **parallelizable, human-free**
  steps are delegated to `.mjs` workflows (in `<BASE>/workflows/`): `spec-explore` (exploration
  fan-out), `architect-panel` (design judge-panel) and `adversarial-review` (multi-lens panel +
  vote). The main loop still does the implementation (Step 5) and presents the gates.
- **Why a workflow and not more loose subagents:** deterministic fan-out wins where diversity
  matters — a 5-lens panel + vote verification finds and filters what a single reviewer can't.
- **Roster (glue rule applied):** Spec (workflow), Architect (workflow), Test-author and Reviewer
  (workflow) each see something different. Don't add a 5th "PM" role: the PM is the spec.
  Test-author stays a single agent on purpose: N parallel authors produce overlapping/conflicting
  tests you'd have to merge — no diversity win, just a merge problem. Implementation (Step 5) stays
  in the main loop: it's stateful (edit→test→adjust) and holds the gates, not a fan-out.
- **Cost:** workflows fan out (several parallel agents) — more tokens than a single subagent.
  Worth it for review/spec; for trivial changes use classic mode (fallback) or don't use this at
  all — the Step 1 triage enforces this. Quota tuning in place: spec explorers run on sonnet at
  low effort (cheap, but their facts are trusted blindly downstream, so not cheaper), verify
  skeptics stay on haiku (proven fine in real runs; the majority vote absorbs a bad refute), the
  3 architects and the conventions review lens run on sonnet (generate/mechanical work — the
  session-model synthesizer judges the designs). The session model is reserved for where a cheap
  miss is unrecoverable: the bug-hunting review lenses (correctness, edge-cases, security,
  test-quality — no vote recovers a finding nobody raised) and both synthesizers. Spec-explore's `facts` feed the architect panel so nobody explores the
  repo twice. Fleets scale to the change: 3 explore angles for small tickets, 3 review lenses for
  small diffs. Plus the earlier tuning: diff captured once (not 40 re-reads), cross-lens dedup,
  severity-scaled verification.
- **If a step saturates or hangs:** restart it; steps are resumable from the branch. The
  workflows are resumable via `resumeFromRunId`.
- **This is level 3 of the adoption ladder.** For trivial tasks, do NOT use this: delegate loose and done.
