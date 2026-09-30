# Templates

Ready-made comments and descriptions, built only from elements that rendered in Jira Cloud
(see [catalogue.md](catalogue.md)). Replace the placeholders in CAPITALS, drop the lines that do
not apply, and run the preview script before posting. Comment templates are Markdown for
`jira_add_comment`; description templates are wiki markup for `description`.

Pick the lightest one that fits. A two-line update does not need panels.

## Comments

### Quick status

```markdown
**DONE / BLOCKED / IN REVIEW: A FEW WORDS**

- WHAT CHANGED FOR THE READER, in one line ([PR #NN](https://github.com/ORG/REPO/pull/NN)).
- WHAT WAS CHECKED, and where, in one line.

**Next:** THE ACTION, BY WHOM. Owner: NAME, or unassigned.
```

### Shipped, ready to test

For a feature that is live and needs eyes. Bullets say what the tester can now do, never how it
works; the screenshot is cropped to the new part and shown at a readable width.

```markdown
**In production (vX.Y.Z), ready to test**

WHERE TO FIND IT: the menu, the button, or the URL.
- WHAT THEY CAN DO NOW, in one line.
- WHAT THEY CAN DO NOW, in one line.
- WHAT IS NOT THERE YET, in one line.

!SCREENSHOT.png|width=800!
_WHAT TO LOOK AT IN THE SCREENSHOT._

[Spec](https://SPEC-URL) · [PR #NN](https://github.com/ORG/REPO/pull/NN)

**Next:** WHO TESTS WHAT, on which case. Owner: NAME.
```

### Status report with panels

For a milestone worth a richer update: a green panel for what is live, a plain table for
evidence, a yellow panel for what is open. Tables go between panels, never inside one.

```markdown
{panel:bgColor=#e3fcef}
### LIVE IN PRODUCTION SINCE DD/MM
ONE SENTENCE ON WHAT NOW WORKS.
- **Endpoint:** `METHOD /path` (version X.Y.Z)
- **PR:** [https://github.com/ORG/REPO/pull/NN|https://github.com/ORG/REPO/pull/NN|smart-link]
- **Where to watch it:** [DASHBOARD NAME](https://DASHBOARD-URL)
{panel}

| Case | Result | Notes |
|------|--------|-------|
| CASE | **{color:#00875a}PASS{color}** | NOTE |
| CASE | **{color:#de350b}FAIL{color}** | NOTE |

{panel:bgColor=#fffae6}
### STILL OPEN
- **ITEM:** WHY IT MATTERS. [PR #NN](https://github.com/ORG/REPO/pull/NN). Owner: NAME.
- **ITEM:** NEXT STEP. Owner: unassigned.
{panel}
```

### Blocker

```markdown
{panel:title=Blocked: SHORT REASON|bgColor=#ffebe6}
- **What is blocked:** THE WORK, and what it stops.
- **What would unblock it:** THE THING, from [~accountid:ACCOUNT_ID].
- **Since:** YYYY-MM-DD
{panel}
```

### Decision record

There is no decision element; this is the stand-in.

```markdown
(/) **Decision (YYYY-MM-DD): THE DECISION IN ONE SENTENCE.**

| Option | For | Against |
|--------|-----|---------|
| **CHOSEN OPTION** | REASON | COST |
| OTHER OPTION | REASON | WHY NOT |

Decided by NAME. Revisit if CONDITION.
```

### Handoff

```markdown
**Handoff: WHERE THIS STANDS FOR THE NEXT PERSON**

- **Done:** WHAT IS FINISHED, with [PR #NN](https://github.com/ORG/REPO/pull/NN).
- **In flight:** WHAT IS HALF-DONE, and on which branch.
- **Next step:** THE VERY NEXT ACTION.
- **Watch out:** THE NON-OBVIOUS TRAP.
---- 
Context: PROJ-123, [DESIGN DOC](https://DOC-URL)
```

### Checklist without checkboxes

Action items are editor-only; icons carry the state.

```markdown
**Release checklist**

- (/) Migrations applied in production
- (/) Feature flag on for 10%
- (!) Dashboard alert pending. Owner: NAME
- (x) Rollback plan not written yet
```

### Status line with a coloured label

Status lozenges are editor-only; coloured bold text is the stand-in.

```markdown
**Status:** **{color:#00875a}ON TRACK{color}** · **Next review:** 2026-10-07
```

Colours: on track `#00875a`, at risk `#ff991f`, blocked `#de350b`, info `#0052cc`.

## Descriptions (wiki markup)

### Story with panels

A common layout for stories: blue context, purple user story, green acceptance criteria. If
the project's other stories use different colours or section titles, copy theirs.

```
{panel:bgColor=#deebff}
*CONTEXT*

WHY THIS EXISTS, WHAT IT DEPENDS ON ([https://SITE.atlassian.net/browse/PROJ-1|https://SITE.atlassian.net/browse/PROJ-1|smart-link]).
{panel}

{panel:bgColor=#eae6ff}
*USER STORY*

* AS A ROLE
* I WANT TO CAPABILITY
* SO THAT OUTCOME
{panel}

{panel:bgColor=#e3fcef}
*ACCEPTANCE CRITERIA*

* CHECKABLE STATEMENT.
* CHECKABLE STATEMENT.
{panel}
```

### Spike with panels

```
{panel:bgColor=#deebff}
h3. *CONTEXT*

THE PROBLEM, AND WHAT IS ALREADY KNOWN.
{panel}

{panel:bgColor=#eae6ff}
h3. *GOALS & SCOPE*

h4. *Goals:*

* QUESTION TO ANSWER.

*Scope:*

* *Included:* WHAT.
* *Excluded:* WHAT.
{panel}

{panel:bgColor=#e3fcef}
h3. *ACCEPTANCE CRITERIA*

* ANSWER WRITTEN ON THE TICKET, WITH EVIDENCE.
* GO / NO-GO WITH THE COST.
{panel}
```

### Bug

```
h3. What happens

WHAT THE USER SEES, WHERE, SINCE WHEN.

h3. Expected

WHAT SHOULD HAPPEN.

h3. How to reproduce

# STEP.
# STEP.

h3. Evidence

* {{THE ONE LOG LINE THAT MATTERS}}
* [DASHBOARD OR TRACE|https://URL]

h3. Impact

WHO, HOW MANY, HOW OFTEN.
```
