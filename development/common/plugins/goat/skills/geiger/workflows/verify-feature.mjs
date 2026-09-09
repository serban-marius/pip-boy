export const meta = {
  name: 'geiger-verify-feature',
  description: 'Feature-verification review panel for a branch diff: did it do what the acceptance criteria asked (worked as intended) AND did it introduce regressions/bugs, with severity-scaled majority-vote verification of each finding',
  phases: [
    { title: 'Review', detail: 'N independent reviewers, one per feature-verification lens' },
    { title: 'Verify', detail: 'severity-scaled refutation (high=3, medium=1, low=0) on a cheap model' },
  ],
}

// args: { baseBranch?: string, criteria?: string, ticketKey?: string, diff?: string }
// Same call contract and return shape as goat's adversarial-review.mjs, so the SKILL only
// swaps the scriptPath. The DIFFERENCE is the lenses: this panel judges the change against what the
// feature was SUPPOSED to do (criteria coverage) first, then hunts for bugs it introduced.
const baseBranch = args?.baseBranch ?? 'main'
const criteria = args?.criteria ?? '(no acceptance criteria provided — infer the intended behavior from the diff and the ticket)'
const ticketKey = args?.ticketKey ?? '(unknown)'
// The orchestrator captures `git diff` ONCE and passes it inline so the panel agents don't each re-run it.
// ponytail: if diff missing, agents fall back to running git themselves (costs more, still works).
const diff = args?.diff

const codeAccess = diff
  ? `The full diff is below. Open a touched file ONLY if you must see surrounding context the diff omits.\n\n<diff base="${baseBranch}">\n${diff}\n</diff>`
  : `Inspect the change yourself: run \`git --no-pager diff ${baseBranch}\` at the repo root, then read touched files as needed.`

const context = `Ticket: ${ticketKey}
Base branch: ${baseBranch}

${codeAccess}

Acceptance criteria the feature was SUPPOSED to satisfy:
${criteria}`

// Two questions, five lenses. "worked as intended" = criteria-coverage; "introduced bugs" = the rest.
const LENSES = [
  {
    key: 'criteria-coverage',
    prompt:
      'This is the "did it work as intended" lens — the most important one. Go through EACH acceptance criterion ONE BY ONE. For each, decide: (a) is it actually implemented by THIS diff? (b) is it asserted by a test that would FAIL if the behavior regressed? Report a HIGH finding for any criterion the code does NOT satisfy (feature did not do what it was asked). Report a MEDIUM finding for any criterion that is satisfied by the code but has NO test asserting it. Name the specific criterion verbatim in each finding\'s title. If every criterion is both met and asserted, return an empty list.',
  },
  {
    key: 'regression-risk',
    prompt:
      'This is the "did it break existing behavior" lens. Hunt for regressions: changed shared/public functions, altered defaults, changed return shapes or error semantics, removed or reordered code paths, behavior other callers depend on. For each changed symbol, ask whether its OTHER (unchanged) callers still behave correctly. Flag broken backward-compatibility or a silently changed contract as HIGH.',
  },
  {
    key: 'correctness',
    prompt:
      'Hunt for logic bugs in the NEW code: wrong conditions, off-by-one, null/empty handling, type coercion, broken control flow, mishandled error paths, incorrect data on the failure path.',
  },
  {
    key: 'edge-cases',
    prompt:
      'Hunt for unhandled edge and error cases in the new behavior: empty/missing input, boundary values, concurrency/ordering, partial failure, idempotency, reversibility. Which acceptance criterion has an untested edge that would break it in production?',
  },
  {
    key: 'contract-drift',
    prompt:
      'Hunt for caller/callee and schema mismatches this change introduced: a signature/return/enum/DTO/API/DB-column change that was NOT propagated to every call site or consumer, mismatched types across a boundary, a serializer/migration that no longer matches the shape it produces or reads.',
  },
]

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'title', 'where', 'why'],
        properties: {
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          title: { type: 'string' },
          where: { type: 'string', description: 'file:line or symbol (or the acceptance criterion, for criteria-coverage)' },
          why: { type: 'string', description: 'what is wrong / unmet and how it manifests' },
          fix: { type: 'string', description: 'concrete suggested fix' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean', description: 'true if the finding is wrong, already handled, or not real' },
    reason: { type: 'string' },
  },
}

phase('Review')
const reviews = await parallel(
  LENSES.map((lens) => () =>
    agent(
      `You are a feature-verification reviewer using the ${lens.key.toUpperCase()} lens. Be skeptical and specific. ${lens.prompt}\n\n${context}\n\nReturn concrete findings by severity. If you find nothing real through this lens, return an empty list — do not invent findings.`,
      { label: `review:${lens.key}`, phase: 'Review', schema: FINDINGS_SCHEMA },
    ),
  ),
)

const raw = reviews
  .filter(Boolean)
  .flatMap((r, i) => (r.findings ?? []).map((f) => ({ ...f, lens: LENSES[i].key })))

// Dedup: lenses overlap (correctness/edge-cases/contract-drift flag the same line). Merge by
// location+title so a duplicate doesn't pay for its own verify panel; keep the highest severity.
// ponytail: normalize where+title, good enough.
const SEV_RANK = { high: 0, medium: 1, low: 2 }
const norm = (s) => (s ?? '').toLowerCase().replace(/\s+/g, ' ').trim()
const byKey = new Map()
for (const f of raw) {
  const key = `${norm(f.where)}|${norm(f.title)}`
  const prev = byKey.get(key)
  if (!prev) {
    byKey.set(key, { ...f, lenses: [f.lens] })
  } else {
    prev.lenses.push(f.lens)
    if (SEV_RANK[f.severity] < SEV_RANK[prev.severity]) prev.severity = f.severity
  }
}
const deduped = [...byKey.values()]
if (raw.length !== deduped.length) log(`Dedup: ${raw.length} raw findings -> ${deduped.length} unique`)

// Cap candidates so a hallucinating lens can't spawn an unbounded verify fan-out. Keep the most severe.
// ponytail: top-N by severity, upgrade to per-lens quotas if a real run overflows.
const MAX_CANDIDATES = 25
const sorted = deduped.sort((a, b) => SEV_RANK[a.severity] - SEV_RANK[b.severity])
const candidates = sorted.slice(0, MAX_CANDIDATES)
if (sorted.length > MAX_CANDIDATES) log(`Capped: ${sorted.length} candidates -> ${MAX_CANDIDATES} (dropped lowest-severity)`)

if (candidates.length === 0) {
  return { verdict: 'apto', confirmed: [], dismissed: [], note: 'All acceptance criteria met and asserted; no bugs found by any lens.' }
}

// Severity-scaled verification. The gate fires on `high` (unmet criterion OR real regression/bug), so spend votes there:
//   high   -> 3 skeptics on the best model (survives if <2 refute)
//   medium -> 1 skeptic, cheap (survives unless refuted)
//   low    -> no panel, reported as-is (never gates)
const VOTES = { high: 3, medium: 1, low: 0 }
const VERIFY_MODEL = 'haiku'
// A skeptic judges ONE finding — give it the LOCATION, not the whole branch diff.
const fileOf = (where) => (where ?? '').split(':')[0].trim()

phase('Verify')
const judged = await parallel(
  candidates.map((f) => () => {
    const n = VOTES[f.severity] ?? 0
    if (n === 0) return Promise.resolve({ ...f, survived: true, refuteVotes: 0, verified: false })
    // criteria-coverage findings often point at a criterion, not a file — fall back to the branch diff for those.
    const target = fileOf(f.where)
    const looksLikePath = target.includes('.') || target.includes('/')
    const codeRef = looksLikePath
      ? `Inspect ONLY the relevant code: read \`${target}\` (or \`git --no-pager diff ${baseBranch} -- ${target}\` for just its change) before deciding. Do not read the whole branch.`
      : `Inspect the change (\`git --no-pager diff ${baseBranch}\`) to decide whether the diff actually satisfies the criterion. Do not read unrelated code.`
    return parallel(
      Array.from({ length: n }, (_, i) => () =>
        agent(
          `Try to REFUTE this feature-verification finding. ${codeRef} Default to refuted=true if the finding is vague, already handled, or not actually reachable. For a criteria-coverage finding, "refuted" means the diff DOES satisfy the criterion (or a test DOES assert it).\n\nFinding (${f.severity}, lens=${f.lens}): ${f.title}\nWhere: ${f.where}\nWhy: ${f.why}`,
          { label: `verify:${f.lens}#${i}`, phase: 'Verify', schema: VERDICT_SCHEMA, model: VERIFY_MODEL, effort: 'low' },
        ),
      ),
    ).then((votes) => {
      const cast = votes.filter(Boolean)
      const refutes = cast.filter((v) => v.refuted).length
      // Survive rule: a majority must refute to kill it (>half). 1 vote -> dies on 1 refute.
      const survived = refutes <= cast.length / 2
      return { ...f, survived, refuteVotes: refutes, verified: true }
    })
  }),
)

const confirmed = judged.filter((f) => f.survived)
const dismissed = judged.filter((f) => !f.survived)
const hasHigh = confirmed.some((f) => f.severity === 'high')

return {
  // 'no apto' when any HIGH survives — i.e. a criterion the feature failed to meet, or a real regression/bug.
  verdict: hasHigh ? 'no apto' : 'apto',
  // `verified: false` marks low-severity findings reported without a refutation panel — treat as leads, not gospel.
  confirmed: confirmed
    .sort((a, b) => SEV_RANK[a.severity] - SEV_RANK[b.severity])
    .map((f) => ({ severity: f.severity, title: f.title, where: f.where, why: f.why, fix: f.fix, lenses: f.lenses, verified: f.verified })),
  dismissed: dismissed.map((f) => ({ title: f.title, lenses: f.lenses, refuteVotes: f.refuteVotes })),
}
