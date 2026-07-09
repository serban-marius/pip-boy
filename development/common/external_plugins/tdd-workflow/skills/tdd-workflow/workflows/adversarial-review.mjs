export const meta = {
  name: 'tdd-workflow-adversarial-review',
  description: 'Adversarial multi-lens review panel for the current branch diff against acceptance criteria, with majority-vote verification of each finding',
  phases: [
    { title: 'Review', detail: 'N independent reviewers, one per lens' },
    { title: 'Verify', detail: 'severity-scaled refutation (high=3, medium=1, low=0) on a cheap model' },
  ],
}

// args: { baseBranch?: string, criteria?: string, ticketKey?: string, diff?: string }
const baseBranch = args?.baseBranch ?? 'main'
const criteria = args?.criteria ?? '(no acceptance criteria provided — infer from the diff and the ticket)'
const ticketKey = args?.ticketKey ?? '(unknown)'
// The orchestrator captures `git diff` ONCE and passes it inline so 40+ agents don't each re-run it.
// ponytail: if diff missing, agents fall back to running git themselves (costs more, still works).
const diff = args?.diff

const codeAccess = diff
  ? `The full diff is below. Open a touched file ONLY if you must see surrounding context the diff omits.\n\n<diff base="${baseBranch}">\n${diff}\n</diff>`
  : `Inspect the change yourself: run \`git --no-pager diff ${baseBranch}\` at the repo root (captures the change committed or not — this review runs pre-commit), then read touched files as needed.`

const context = `Ticket: ${ticketKey}
Base branch: ${baseBranch}

${codeAccess}

Acceptance criteria to check against:
${criteria}`

const LENSES = [
  { key: 'correctness', prompt: 'Hunt for logic bugs: wrong conditions, off-by-one, null/empty handling, type coercion, broken control flow, mismatched contracts between caller and callee.' },
  { key: 'edge-cases', prompt: 'Hunt for unhandled edge and error cases: empty/missing input, boundary values, concurrency/ordering, partial failure, idempotency, reversibility. Which acceptance criterion has NO test?' },
  { key: 'security', prompt: 'Hunt for security and data-safety issues: injection, missing authz at trust boundaries, secrets in code, unsafe deserialization, data loss on the error path.' },
  { key: 'conventions', prompt: 'Hunt for broken project conventions, naming, dead code, leftover debug, and design debt that a maintainer would have to fix later. Read sibling files to learn the conventions first.' },
  { key: 'test-quality', prompt: 'Judge whether the tests prove BEHAVIOR or just cover lines. Would they survive mutation testing? Is there a test that cannot fail? Is each acceptance criterion asserted, not just exercised?' },
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
          where: { type: 'string', description: 'file:line or symbol' },
          why: { type: 'string', description: 'what is wrong and how it manifests' },
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
      `You are an adversarial code reviewer using the ${lens.key.toUpperCase()} lens. Be skeptical and specific. ${lens.prompt}\n\n${context}\n\nReturn concrete findings by severity. If you find nothing real through this lens, return an empty list — do not invent findings.`,
      { label: `review:${lens.key}`, phase: 'Review', schema: FINDINGS_SCHEMA },
    ),
  ),
)

const raw = reviews
  .filter(Boolean)
  .flatMap((r, i) => (r.findings ?? []).map((f) => ({ ...f, lens: LENSES[i].key })))

// Dedup: the 5 lenses overlap heavily (correctness/edge-cases/test-quality flag the same line).
// Merge by location+title so a duplicate doesn't pay for its own verify panel. Keep the highest
// severity and remember which lenses raised it. ponytail: normalize where+title, good enough.
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

// Cap candidates so a hallucinating lens can't spawn an unbounded verify fan-out. Keep the most
// severe; a dropped low never gates anyway. ponytail: top-N by severity, upgrade to per-lens quotas if a real run overflows.
const MAX_CANDIDATES = 25
const sorted = deduped.sort((a, b) => SEV_RANK[a.severity] - SEV_RANK[b.severity])
const candidates = sorted.slice(0, MAX_CANDIDATES)
if (sorted.length > MAX_CANDIDATES) log(`Capped: ${sorted.length} candidates -> ${MAX_CANDIDATES} (dropped lowest-severity)`)

if (candidates.length === 0) {
  return { verdict: 'apto', confirmed: [], dismissed: [], note: 'No findings from any lens.' }
}

// Severity-scaled verification. The gate only fires on `high`, so spend votes there:
//   high   -> 3 skeptics on the best model (survives if <2 refute)
//   medium -> 1 skeptic, cheap (survives unless refuted)
//   low    -> no panel, reported as-is (never gates)
// Skeptics use a cheap model: "is this one finding real?" is a narrow task, full model is overkill.
const VOTES = { high: 3, medium: 1, low: 0 }
const VERIFY_MODEL = 'haiku'
// A skeptic judges ONE finding — give it the LOCATION, not the whole branch diff. Inlining the full
// diff into every verifier would re-cost exactly what passing it once was meant to save.
const fileOf = (where) => (where ?? '').split(':')[0].trim()

phase('Verify')
const judged = await parallel(
  candidates.map((f) => () => {
    const n = VOTES[f.severity] ?? 0
    if (n === 0) return Promise.resolve({ ...f, survived: true, refuteVotes: 0, verified: false })
    const codeRef = `Inspect ONLY the relevant code: read \`${fileOf(f.where) || f.where}\`${fileOf(f.where) ? ` (or \`git --no-pager diff ${baseBranch} -- ${fileOf(f.where)}\` for just its change)` : ''} before deciding. Do not read the whole branch.`
    return parallel(
      Array.from({ length: n }, (_, i) => () =>
        agent(
          `Try to REFUTE this review finding. ${codeRef} Default to refuted=true if the finding is vague, already handled, or not actually reachable.\n\nFinding (${f.severity}, lens=${f.lens}): ${f.title}\nWhere: ${f.where}\nWhy: ${f.why}`,
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
  verdict: hasHigh ? 'no apto' : 'apto',
  // `verified: false` marks low-severity findings reported without a refutation panel — treat as leads, not gospel.
  confirmed: confirmed
    .sort((a, b) => SEV_RANK[a.severity] - SEV_RANK[b.severity])
    .map((f) => ({ severity: f.severity, title: f.title, where: f.where, why: f.why, fix: f.fix, lenses: f.lenses, verified: f.verified })),
  dismissed: dismissed.map((f) => ({ title: f.title, lenses: f.lenses, refuteVotes: f.refuteVotes })),
}
