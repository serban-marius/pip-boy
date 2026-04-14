# Diagrams

Generate interactive visual flow diagrams as standalone HTML files using [Mermaid.js](https://mermaid.js.org/).

## What it does

The `/diagrams` skill generates self-contained HTML files with Mermaid.js diagrams that open directly in your browser. It reads your code first, then produces clean, styled diagrams with contextual callout boxes.

## Supported diagram types

- **Sequence diagrams** -- API calls, job chains, event flows
- **Flowcharts** -- Decision logic, branching paths, process steps
- **State diagrams** -- State machines, status transitions, lifecycle stages
- **Class diagrams** -- Relationships, interfaces, module structure
- **ER diagrams** -- Database relationships, data models
- **C4 diagrams** -- System architecture, service boundaries

## Usage

Ask Claude to visualize something:

- "Draw a diagram of the authentication flow"
- "Visualize how the queue worker processes jobs"
- "Compare current vs proposed architecture for the payment service"
- `/diagrams`

## Plugin structure

```
diagrams/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── diagrams/
│       └── SKILL.md
└── README.md
```
