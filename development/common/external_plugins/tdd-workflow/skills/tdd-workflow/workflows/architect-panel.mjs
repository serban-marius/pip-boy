export const meta = {
  name: 'tdd-workflow-architect-panel',
  description: 'Architecture phase as a judge-panel: 3 independent design perspectives explore the repo in parallel, then a synthesizer reconciles them into one actionable plan',
  phases: [
    { title: 'Panel', detail: '3 architects design in parallel: convention-first · risk-first · yagni' },
    { title: 'Synthesis', detail: 'one synthesizer reconciles the 3 designs into a single plan' },
  ],
}

// args: { spec: object|string, ticketKey?: string, hints?: string[] }
const ticketKey = args?.ticketKey ?? '(unknown)'
const hints = Array.isArray(args?.hints) ? args.hints : []
const specText = typeof args?.spec === 'string' ? args.spec : JSON.stringify(args?.spec ?? {}, null, 2)

const context = `Ticket: ${ticketKey}

Approved spec:
${specText}${hints.length ? `\n\nHints to focus on:\n- ${hints.join('\n- ')}` : ''}

Explore the ACTUAL repo (grep/read) before proposing — respect existing conventions, look at sibling code.
Do NOT write the implementation. Deliver a PLAN only.`

// Each architect returns a design, not code.
const DESIGN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['approach', 'files'],
  properties: {
    approach: { type: 'string', description: 'the design in 3-5 lines' },
    files: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['path', 'change'],
        properties: {
          path: { type: 'string' },
          change: { type: 'string', description: 'what this file gets, and why here' },
        },
      },
    },
    contracts: { type: 'array', items: { type: 'string' }, description: 'interfaces/contracts between the pieces' },
    order: { type: 'array', items: { type: 'string' }, description: 'recommended implementation order' },
    risks: { type: 'array', items: { type: 'string' }, description: 'architectural risks / things that could break' },
  },
}

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['chosenApproach', 'files', 'order'],
  properties: {
    chosenApproach: { type: 'string' },
    rationale: { type: 'string', description: 'what was taken from each perspective and what was discarded, and why' },
    files: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['path', 'change'],
        properties: { path: { type: 'string' }, change: { type: 'string' } },
      },
    },
    contracts: { type: 'array', items: { type: 'string' } },
    order: { type: 'array', items: { type: 'string' } },
    risks: { type: 'array', items: { type: 'string' } },
  },
}

// Three genuinely different design lenses — diversity is the point, not redundancy.
const LENSES = [
  {
    key: 'convention-first',
    prompt: 'You are the CONVENTION-FIRST architect. Mirror the existing patterns as closely as possible: same layering, naming, wiring (service providers, bindings), how similar features are already built. Minimal deviation — a maintainer should not be able to tell this was added later. Read sibling code to learn the conventions before proposing.',
  },
  {
    key: 'risk-first',
    prompt: 'You are the RISK-FIRST architect. Minimize blast radius: isolate the change, keep it reversible, guard the error and side-effect paths (observers, hooks, events, transactions that could be left half-done on throw). Prefer a design where a bug in this change cannot corrupt existing behavior. Call out every risk explicitly.',
  },
  {
    key: 'yagni',
    prompt: 'You are the YAGNI/PONYTAIL architect: a lazy senior = efficient. The best code is the code never written. Climb the ladder — does this need to exist?, does the stdlib/an installed dep do it?, can it be a few lines? Propose the MINIMUM design that satisfies the spec. No interface with one implementation, no config for a constant, no speculative abstraction.',
  },
]

phase('Panel')
const designs = await parallel(
  LENSES.map((lens) => () =>
    agent(
      `${lens.prompt}\n\n${context}`,
      { label: `architect:${lens.key}`, phase: 'Panel', schema: DESIGN_SCHEMA },
    ).then((d) => (d ? { lens: lens.key, ...d } : null)),
  ),
)

const valid = designs.filter(Boolean)
if (valid.length === 0) {
  return { plan: null, designs: [], note: 'No architect produced a design.' }
}

phase('Synthesis')
const plan = await agent(
  `You are the SYNTHESIZER architect. You have ${valid.length} independent designs for the same spec, each from a different lens. ` +
    `Reconcile them into ONE actionable plan: pick the best approach, state what you take from each design and what you discard and why, ` +
    `then give the concrete file list, contracts, recommended implementation order, and residual risks. ` +
    `Favor the convention-first structure unless risk-first or yagni raises something that genuinely outweighs it.\n\n${context}\n\n` +
    `Designs:\n${JSON.stringify(valid, null, 2)}`,
  { label: 'synthesize:plan', phase: 'Synthesis', schema: PLAN_SCHEMA },
)

return { plan, designs: valid }
