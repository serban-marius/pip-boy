# 003 · overseer rework

Living spec: requirements are added here as they are given, before any code changes.

## Why

Code written by an agent in a PHP service came out with rationale docblocks, `@param` lines that carry
prose, and an `__invoke` of ~80 lines whose steps you can only follow by reading every one of them. Overseer was not installed there, but even
installed it would only have *reminded* about the comments after each edit, and it says nothing about
function size or complexity.

## Requirements

### R1 · Names explain the code, comments do not

Allowed in code, nothing else:

- type annotations, bare: `@param <type> $name`, `@return <type>`, `@var <type>`, `@throws <Class>`,
  `@template`, `@extends`, `@implements`, `@property`, `@method`, `@phpstan-*`, `@psalm-*`;
- tool and framework directives (`phpcs:`, `eslint-`, `noqa`, `@ts-`, `@dataProvider`, `@covers`…), attributes, shebangs;
- one-line `ponytail:` shortcut markers.

Changes from today:

| Case | Today | After |
|---|---|---|
| A docblock or line comment that explains (`Gathers the sources: catalog facts, the publisher page …`) | reminder after the edit | reminder after the edit **and block at `git commit`** |
| An annotation followed by prose (`@param list<string> $excludedTerms facts using these terms …`, `@return list<string> ids where …`) | allowed (any `@` line passes) | prose: only the bare annotation stays |
| Other tags with prose (`@see`, `@todo`, `@deprecated …`, `@internal`) | allowed | prose |

### R2 · Small functions, small classes

A function says what happens through the names of the functions it calls. Measured on the functions an
edit touches (legacy functions nobody touches are left alone):

| Metric | Limit | Seen in that service |
|---|---|---|
| Lines in a function body (no blanks, no comments) | 15 | `__invoke` 78, `build` 28, `verify` 19, `context` 17 |
| Nesting depth inside a function | 2 | `verify` 3, `supportingSources` 3 |
| Parameters (constructors exempt) | 4 | `__invoke` 10, `build` 7 |
| Code lines in a file (no blanks, no comments) | 200 | the builder class, 242 |

Effect: reminder after the edit naming the function and the metric, block at `git commit`.
Heuristic, no per-language tooling: brace languages by `function`/`fn`/`func`/method signatures and
brace matching, Python by `def` and indentation.

## How we'll know it works

`hooks/overseer.test.sh`, plus a run against the two service files that prompted this:

- the rationale docblocks and `@param … $excludedTerms facts using …` are reported, and a commit with them is blocked;
- `@param list<SourceSnapshot> $snapshots` and `@return array{0: Outcome, 1: float}` pass;
- the long `__invoke`, the nesting-3 `verify` and the 242-line class are reported with their metric; a commit with them is blocked;
- a long legacy function in a file that is edited elsewhere is not reported.

## Decided

- Limits as proposed: 15 body lines, nesting 2, 4 parameters, 200 lines per file.
- A change inside a long legacy function makes it subject to R2: touch it, split it.
- R2 measures production code only; tests are exempt.
- Python docstrings stay out of R1 for now.
