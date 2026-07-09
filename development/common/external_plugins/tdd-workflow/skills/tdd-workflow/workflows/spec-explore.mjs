export const meta = {
  name: 'tdd-workflow-spec-explore',
  description: 'Fan out read-only explorers over the codebase to ground a JIRA ticket, then synthesize an implementable spec draft',
  phases: [
    { title: 'Explore', detail: 'parallel explorers, one per angle' },
    { title: 'Synthesize', detail: 'one spec draft from all findings' },
  ],
}

// args: { ticket: string, hints?: string[] }
const ticket = args?.ticket ?? '(no ticket text provided)'
const hints = Array.isArray(args?.hints) ? args.hints : []

// Distinct exploration angles. Each explorer is blind to the others — diversity beats one big search.
const ANGLES = [
  { key: 'entrypoints', prompt: 'Find where this behavior would enter the system: controllers, jobs, listeners, commands, cron. Identify the single best choke point for the change and why.' },
  { key: 'domain', prompt: 'Find the entities, value objects, and domain services this touches. What is the real identity/key of the data involved? What invariants already exist?' },
  { key: 'precedent', prompt: 'Find existing patterns to copy: similar config-driven lists/flags, similar guards/filters, how skips/errors are logged, how this kind of thing is wired (service provider, bindings).' },
  { key: 'tests', prompt: 'Find the test conventions and the exact test file(s) that would cover this: base class, naming, fakes/builders, how the subject is constructed and asserted. Cite the file to mirror.' },
  { key: 'constraints', prompt: 'Find constraints that bound the design: a constitution/spec under specs/ or .specify, coding standards, things that must NOT be touched (e.g. base/framework code), and existing protections that this must not break.' },
  { key: 'side-effects', prompt: 'Find what fires implicitly around the writes/operations this touches: model observers, lifecycle hooks (creating/saving/deleting), event listeners, DB triggers, outbox/transactional-event publishers, and any implicit transactions they open. Crucially, what happens on the ERROR path — does a hook open a transaction or emit an event that is left dangling/half-done if the operation throws?' },
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
        required: ['claim', 'evidence'],
        properties: {
          claim: { type: 'string', description: 'a concrete fact about the codebase relevant to the ticket' },
          evidence: { type: 'string', description: 'file:line or symbol that backs it' },
        },
      },
    },
  },
}

const SPEC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'acceptanceCriteria', 'edgeCases', 'openQuestions'],
  properties: {
    summary: { type: 'string', description: 'expected behavior in 3-5 lines' },
    chokePoint: { type: 'string', description: 'where the change lands (class/method) and why' },
    acceptanceCriteria: { type: 'array', items: { type: 'string' }, description: 'verifiable, mapped to real code' },
    edgeCases: { type: 'array', items: { type: 'string' }, description: 'error/edge cases the ticket omits but matter' },
    openQuestions: { type: 'array', items: { type: 'string' }, description: 'open questions / assumptions to confirm at the gate' },
  },
}

const context = `JIRA ticket:\n${ticket}${hints.length ? `\n\nHints to focus on:\n- ${hints.join('\n- ')}` : ''}`

phase('Explore')
const explored = await parallel(
  ANGLES.map((a) => () =>
    agent(
      `You are a read-only code explorer for the "${a.key}" angle. ${a.prompt}\n\n${context}\n\nExplore the actual repo (grep/read). Return concrete, evidence-backed facts only — no speculation, no code changes.`,
      { label: `explore:${a.key}`, phase: 'Explore', schema: FINDINGS_SCHEMA, agentType: 'Explore' },
    ),
  ),
)

const facts = explored
  .filter(Boolean)
  .flatMap((r, i) => (r.findings ?? []).map((f) => `- [${ANGLES[i].key}] ${f.claim} (${f.evidence})`))
  .join('\n')

phase('Synthesize')
const spec = await agent(
  `You are the SPEC agent. Turn the JIRA ticket into an implementable spec using ONLY the grounded findings below — do not write code. Be concrete and skeptical of a vague ticket. Acceptance criteria must be verifiable and tied to the real code the explorers found.\n\n${context}\n\nGrounded findings:\n${facts}`,
  { label: 'synthesize:spec', phase: 'Synthesize', schema: SPEC_SCHEMA },
)

return { spec, facts }
