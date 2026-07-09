# TDD Workflow

Take a JIRA ticket from ticket to a PR with a team of specialized agents, in TDD, with two human gates. You are the team's architect, not the glue.

Stack-agnostic (detects the project). Hybrid design: the skill keeps the two human gates (after the spec, before the commit) and delegates the parallelizable, human-free steps to deterministic `.mjs` workflows.

## Skills

### tdd-workflow

Ticket → PR pipeline: **Spec → Architect → failing tests (TDD) → implementation → independent review → commit/PR**, with a stop after the spec (Gate 1) and before the commit (Gate 2).

**Pipeline:**

- **Spec** — the `spec-explore` workflow fans out read-only explorers over distinct angles (entrypoints, domain, precedent, tests, constraints, side-effects) and synthesizes an evidence-backed, implementable spec draft.
- **Architect** — the `architect-panel` workflow runs 3 independent designs in parallel through distinct lenses (convention-first, risk-first, yagni), then a synthesizer reconciles them into one plan.
- **Tests first** — an independent test-author writes tests for each acceptance criterion; the runner confirms they are RED before any implementation.
- **Implementation** — the main loop implements to GREEN, iterating implement → test → adjust.
- **Review** — the `adversarial-review` workflow reviews the diff through 5 lenses (correctness, edge-cases, security, conventions, test-quality), then verifies findings with severity-scaled adversarial voting (high=3 skeptics, medium=1, low reported as-is). The diff is captured once and passed in; skeptics run on a cheap model and inspect only their finding's location — tuned to keep token cost down.

If the repo uses spec-kit (`specs/` + `.specify/`), the approved spec is persisted as a versioned artifact (`spec.md` / `research.md` / `checklists`). If not, it asks.

**Usage:**

Say any of: `/tdd-workflow PROJ-123`, "implement ticket X with agents", "take this jira task and build it with TDD", "from jira to PR with agents". Spanish triggers also work.

**Requirements:**

- **JIRA MCP** — required to fetch the ticket in Step 1 (`mcp__atlassian-local__jira_get_issue` / `jira_search`). Without it, provide the ticket text directly.
- **context7** — required by the architect panel's docs-backed lens and by any step that verifies library/stdlib usage against official docs. Install the `context7` plugin from this marketplace.
- **ponytail** — required for the YAGNI/minimal-design lens in the architect panel (climbs the laziness ladder: does this need to exist? does the stdlib do it? can it be one line?). The skill's design assumes ponytail's judgment is available.
- **`Workflow` tool** — needed for the fan-out steps (spec-explore, architect-panel, adversarial-review). Without it, each parallel step falls back to a single subagent.

### outcome-review

Review the outputs of a developed feature: verify worked-as-intended and detect regressions.

**Two phases:**
- **Phase 1 (pre-merge)** — run the spec-driven tests and adversarial review, post a PR comment with the verdict (pass/fail/review needed).
- **Phase 2 (post-deploy loop)** — diff production error signatures against a pre-deploy baseline, triage new/worsened errors to Jira, and loop until resolved. No Slack notifications; errors surface in Jira only.

**Modes:** `/outcome-review <pr|branch>` (run phase 1), `--watch <pr>` (loop phase 2), `--status <pr>` (check phase 2 progress), `--stop <pr>` (end phase 2 loop).

**Note:** Phase 2 assumes the Softonic production stack — Elasticsearch via `$ES_CREDS` and Jira project `DS`.
