---
name: diagrams
description: "Generate interactive visual flow diagrams as HTML files with Mermaid.js. Use when the user asks to: (1) draw, visualize, or diagram a code flow, (2) show how something works or will work, (3) compare current vs proposed architecture, (4) explain a design, plan, or system visually, (5) create sequence diagrams, flowcharts, or any architectural diagram. Triggers on phrases like 'draw a diagram', 'visualize the flow', 'show me how it works', 'diagram the plan', '/diagrams'."
---

# Diagrams

Generate interactive Mermaid.js diagrams rendered as standalone HTML files that open in the browser.

## When to Use

- Explaining how a system, feature, or flow currently works
- Proposing a new design or architecture visually
- Comparing current state vs proposed changes (refactors, migrations, new features, bug fixes)
- Visualizing request lifecycles, event chains, job pipelines, or service interactions
- Communicating architecture to stakeholders or teammates
- Planning implementation before writing code

## Workflow

### 1. Understand What to Visualize

Determine the intent — the user may want one or more of:

| Intent | Approach |
|--------|----------|
| **Explain how it works** | Single set of diagrams showing the current flow |
| **Propose something new** | Diagrams showing the planned design |
| **Compare current vs proposed** | Side-by-side sections: "Current" then "Proposed" with matching structure |
| **Debug a problem** | Current (broken) flow, then fixed flow highlighting the change |
| **Plan an implementation** | High-level architecture + detailed component interactions |

### 2. Read the Relevant Code

Before generating any diagram, read the relevant code to understand:
- Entry points (controllers, jobs, commands, listeners)
- Decision points (conditionals, fallbacks, error handling)
- Data transformations (where values are computed, stored, passed)
- External interactions (APIs, databases, queues, events)
- Service boundaries and communication patterns

### 3. Choose Diagram Types

Select the most appropriate Mermaid diagram types. Combine multiple in a single HTML file:

| Type | Use When |
|------|----------|
| `sequenceDiagram` | Interactions between components over time (API calls, job chains, event flows) |
| `flowchart TD/LR` | Decision logic, branching paths, conditional flows, process steps |
| `stateDiagram-v2` | State machines, status transitions, lifecycle stages |
| `classDiagram` | Class relationships, interfaces, dependencies, module structure |
| `erDiagram` | Database relationships, data models |
| `C4Context` / `C4Container` | High-level system architecture, service boundaries |

### 4. Generate the HTML File

Create a self-contained HTML file with:
- Mermaid.js loaded from CDN
- Clean styling with sections, headings, and contextual callout boxes
- All diagrams rendered inline
- Summary tables or context boxes where helpful

**File location:** Always save to a temporary location:
- `{project_root}/{ticket-or-topic}-diagrams.html` for project-specific diagrams
- `/tmp/{topic}-diagrams.html` for general diagrams

### 5. Open in Browser

```bash
open {path-to-html-file}
```

### 6. Remind to Clean Up

After opening, remind the user that the file is temporary and should not be committed.

## HTML Template

Use this structure for generated diagram files:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{Title}</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; background: #f8f9fa; }
    h1 { color: #333; border-bottom: 2px solid #dee2e6; padding-bottom: 10px; }
    h2 { color: #495057; margin-top: 40px; }
    h3 { color: #868e96; }
    .diagram { background: white; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .callout { padding: 15px; margin: 20px 0; border-radius: 4px; }
    .callout-warning { background: #fff3cd; border-left: 4px solid #ffc107; }
    .callout-danger { background: #f8d7da; border-left: 4px solid #dc3545; }
    .callout-success { background: #d4edda; border-left: 4px solid #28a745; }
    .callout-info { background: #d1ecf1; border-left: 4px solid #17a2b8; }
    .callout-neutral { background: #e9ecef; border-left: 4px solid #6c757d; }
    code { background: #e9ecef; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
    table { border-collapse: collapse; width: 100%; margin: 10px 0; }
    th, td { border: 1px solid #dee2e6; padding: 8px 12px; text-align: left; }
    th { background: #e9ecef; }
  </style>
</head>
<body>
  <h1>{Title}</h1>

  <!-- Use callout boxes for context — pick the ones that fit -->
  <div class="callout callout-info"><strong>Context:</strong> ...</div>
  <div class="callout callout-neutral"><strong>Goal:</strong> ...</div>
  <div class="callout callout-success"><strong>Approach:</strong> ...</div>
  <div class="callout callout-warning"><strong>Trade-off:</strong> ...</div>
  <div class="callout callout-danger"><strong>Risk:</strong> ...</div>

  <!-- Wrap each diagram in a .diagram div -->
  <div class="diagram">
    <pre class="mermaid">
    sequenceDiagram
        participant A as Component A
        participant B as Component B
        A->>B: action
        B-->>A: response
    </pre>
  </div>

  <script>mermaid.initialize({theme: 'default', securityLevel: 'loose'});</script>
</body>
</html>
```

### Callout Box Usage Guide

Use callouts that match the intent, not just bugs:

| Class | Use For |
|-------|---------|
| `callout-info` | Context, background, "how it works today" |
| `callout-neutral` | Goals, requirements, scope |
| `callout-success` | Proposed solution, benefits, what improves |
| `callout-warning` | Trade-offs, caveats, things to watch |
| `callout-danger` | Risks, breaking changes, known issues |

## Mermaid Tips

- Use `Note over X: text` in sequence diagrams for inline annotations
- Use `<br/>` for line breaks inside notes and labels
- Use `style NodeId fill:#color,color:#fff` in flowcharts to highlight important nodes
- Color convention: green (`#51cf66`) for new/added, blue (`#339af0`) for existing/unchanged, orange (`#ff922b`) for modified, red (`#ff6b6b`) for removed/problematic
- Keep node labels short; use notes or callout boxes for longer explanations
- For current vs proposed comparisons, use two separate sections with matching structure so the reader can compare visually
- When showing a plan, use numbered phases or steps as section headers

## Output

After generating and opening the file, display:
- The file path
- A brief description of what diagrams are included
- A reminder that the file is temporary and should not be committed
