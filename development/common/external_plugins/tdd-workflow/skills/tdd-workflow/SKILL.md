---
name: tdd-workflow
description: Take a JIRA task from ticket to PR with a team of specialized agents, in TDD and with human brakes. Pipeline - Spec (PM/Spec-Driven) -> Architect -> Failing tests (TDD) -> Implementation to green -> Independent reviewer -> commit/PR. Hybrid model- the skill keeps the two human gates (after the spec and before the commit) and delegates the parallelizable steps to .mjs workflows (spec-explore: exploration fan-out; architect-panel: design judge-panel; adversarial-review: multi-lens panel + vote). Stack-agnostic (detects the project). If the repo uses spec-kit (specs/ + .specify/), persists the spec as a versioned artifact (spec.md/research.md/checklists); if not, it asks. Triggers- "/tdd-workflow PROJ-123", "implement ticket X with agents", "take this jira task and build it with TDD", "from jira to PR with agents", "tdd-workflow", "jira-tdd". Spanish triggers also- "implementa el ticket X con agentes", "coge esta tarea de jira y móntala con TDD", "de jira a PR con agentes".
---

# tdd-workflow · from a JIRA ticket to a PR, with a team of agents

Orchestrate a team of specialized agents to implement a JIRA task following TDD,
**with two human gates**. You are the team's architect, not the glue.

## Philosophy (do not break it)

- **Glue rule:** every role exists because it sees something the previous one can't. Don't add decorative agents.
- **The validator is INDEPENDENT:** the reviewer did not write the code. "An agent that reviews itself, doesn't review."
- **Real TDD:** tests are written FIRST, seen RED, and only then is code implemented to GREEN.
- **Brakes on real code:** you do NOT go ticket-to-PR on autopilot. You stop after the spec and before the commit.

## The argument

`$ARGUMENTS` = the ticket key (e.g. `PROJ-123`). If absent, ask for it.

## Prerequisites (required)

- **JIRA MCP** — to fetch the ticket in Step 1 (`mcp__atlassian-local__jira_get_issue` / `jira_search`). If it's not available, ask the user to paste the ticket text and continue.
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
   - **Smoke-test the runner BEFORE continuing:** knowing the command isn't enough; confirm it can RUN. Run something trivial (a small existing test, `--version`, or the runner empty). If the test environment isn't alive (DB down, k8s/Docker cluster not up, container stopped), **stop and ask the user to bring it up NOW** — don't discover it mid-Step 4, after you've written the tests and can't see red. Heavy environments (KIND/k8s, sail/docker, remote DB) are the #1 cause of late blocking.
3. **Capture the base branch, then create the work branch.** Don't assume `main` — many repos (e.g. Laravel/`develop`, `master`) fork elsewhere. Record the branch you're forking from (`git rev-parse --abbrev-ref HEAD`, or the remote default via `git symbolic-ref refs/remotes/origin/HEAD`); call it `<BASE_BRANCH>`. Then `git checkout -b feat/<PROJ-123>-<short-slug>`. Pass `<BASE_BRANCH>` to every `git diff` and to the reviewer workflow below — `main` is only a fallback.
4. **Detect spec-kit**: does the repo have `specs/` and/or `.specify/`? If **yes**, this pipeline persists the spec artifacts (see Step 2.5). If **no**, do NOT assume: ask the user *"this repo doesn't use spec-kit — should I just generate the spec in chat (as usual) or do you want to adopt it?"* and respect the answer. Check whether `scripts/check-specs.sh` exists for validation.

## Step 1 · 📋 Fetch the JIRA ticket

Use the Atlassian MCP: `mcp__atlassian-local__jira_get_issue` with the key. If it doesn't resolve,
search with `mcp__atlassian-local__jira_search`. Extract: title, description, acceptance criteria,
relevant comments, attachments/links. Summarize the ticket in 3-4 lines.

## Step 2 · 🧭 SPEC (parallel exploration workflow)

Instead of a single subagent, launch the **workflow** `spec-explore` — it fans out read-only
explorers across distinct angles (entrypoints, domain, precedent, tests, constraints) and
synthesizes a spec draft from evidence-backed findings. More coverage than a single sequential
exploration.

Invoke it with the `Workflow` tool, passing the skill's script and the ticket:

```
Workflow({
  scriptPath: "<BASE>/workflows/spec-explore.mjs",
  args: { ticket: "<ticket text>", hints: ["<optional hint>", ...] }
})
```

where `<BASE>` is the "Base directory for this skill" shown when it's invoked. Returns
`{ spec, facts }`: `spec` carries summary, chokePoint, acceptanceCriteria, edgeCases, openQuestions.

(If the `Workflow` tool isn't available in the environment, fall back to classic mode: a
general-purpose `Agent` subagent with the same brief — summary, verifiable criteria, edge cases,
open questions — exploring the code before writing.)

### 🚦 GATE 1 — present the spec and STOP
Show the spec + criteria + assumptions to the user. Ask: **"Do I approve this spec or adjust something?"**
**End the turn and wait for their answer.** Don't proceed without an explicit OK. Incorporate their changes if asked.

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
  args: { spec: <approved spec object or text>, ticketKey: "<PROJ-123>", hints: ["<optional hint>", ...] }
})
```

Returns `{ plan, designs }`: `plan` carries chosenApproach, rationale (what it took/discarded from
each lens), files (path + change), contracts, order, risks.

(If `Workflow` isn't available, fall back to classic mode — a single subagent: *"You are the
ARCHITECT agent. Given this approved spec and the repo code, design WHERE and HOW it fits: files
created/touched, layers, contracts, dependencies. Respect existing conventions (look first). Do NOT
implement: deliver the PLAN — files + what each change does + recommended order + risks."*)

Show the plan in 5-6 lines (not a gate; it's so the user sees it go by). If the plan reveals
the spec was wrong, go back to Gate 1.

**Spec-kit**: if the repo uses it, dump the plan's evidence (paths, classes, contracts, risks, links
to Jira/PR) into `specs/NNN-<slug>/research.md` — implementation details that `spec.md` does NOT carry go here.

## Step 4 · 🔴 TEST-AUTHOR agent (failing tests)

Launch an independent subagent (does not implement):

> You are the TEST-AUTHOR agent. Write the tests that verify the spec's ACCEPTANCE CRITERIA,
> following AAA and the project's framework. One test per criterion + edge cases. Do NOT write the
> implementation; the tests must FAIL because the functionality doesn't exist yet. Write the test files.

Then **run the test command and CONFIRM they are RED.** If they pass green without implementation,
something is wrong (a test that proves nothing) → fix it. Show the red. *"A test that can't fail proves nothing."*

**Spec-kit**: if the repo uses it, fill `specs/NNN-<slug>/checklists/requirements.md` — a spec-quality
checklist (completeness/clarity/consistency) mapping each criterion to its FR. Commit the 3
spec files alongside the feature (or as a spec commit) in Step 7.

## Step 5 · 🟢 Implementation (YOU do it, the main loop)

Implement following the architect's PLAN, the minimum to turn the tests GREEN. Iterate:
implement → run tests → adjust, until all pass. Respect conventions and, if present,
run the stack's linter/formatter. Do NOT touch the tests to make them pass (except a genuine test bug).

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
Show: change summary, tests green, reviewer findings. Ask:
**"Do I commit and open the PR, or adjust something?"** **End the turn and wait for the OK.**

## Step 7 · 🚀 Commit + PR (after the OK)

- If the project is Laravel and the `laravel-workflow:ship` skill exists, **delegate to it** (commit + duster + PR).
- Otherwise: commit with a message referencing the ticket (`PROJ-123: <title>`), push, and `gh pr create`
  with body = spec + what was done + how it was validated + open reviewer findings. Link the JIRA ticket.

---

## Notes

- **Hybrid model (skill + workflows):** the SKILL keeps BOTH human gates (Gate 1 after the
  spec, Gate 2 before the commit) — that's non-negotiable and why this stays a skill, not a
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
  all. The adversary is already tuned for quota: diff captured once (not 40 re-reads), dedup of
  findings overlapping across lenses, severity-scaled verification, and skeptics on a cheap model.
  The bulk of the cost was skeptics re-reading the whole branch — that no longer happens.
- **If a step saturates or hangs:** restart it; steps are resumable from the branch. The
  workflows are resumable via `resumeFromRunId`.
- **This is level 3 of the adoption ladder.** For trivial tasks, do NOT use this: delegate loose and done.
