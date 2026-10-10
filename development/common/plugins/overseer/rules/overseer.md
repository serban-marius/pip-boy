---
name: overseer
description: The delivery cycle overseer enforces with hooks - spec, red, green, commit, small PR, no prose comments, small functions - and how to clear each block
---

# overseer is on in this repo

Hooks enforce this cycle. When one blocks you, fix the cause it names and retry.

1. **Spec first.** Before touching production code, the branch has a spec: `specs/NNN-<slug>/spec.md` (spec-kit layout, also when the repo has no spec tooling) or an `openspec/changes/<name>/` proposal. Say what changes and how we'll know it works. A change with no behaviour to specify (tooling, config, a lint fix) declares it instead, in a commit before touching code: `git commit --allow-empty -m "chore: <what>" -m "Spec impact: None — <why>"`.
2. **Red first.** Write or change a test for the behaviour, run it, and watch it fail. Only then touch production code.
3. **Green commits.** Commit only after a test run that passed, with nothing edited since. Run the tests in their own command, then commit in another.
4. **Commits carry their test.** A commit that changes production code should change a test too. A pure refactor is the exception.
5. **Smallest PRs the feature allows.** Cut by function, not by size: each PR is the smallest piece that builds, passes its tests and can be reviewed and merged on its own. When the feature needs more than one, make a stack, each PR based on the previous branch. To cut one, use the `split-pr-stack` skill (caravan). A PR against the default branch with over ~400 lines of production code is blocked until it goes through that skill, or says in its body why it cannot be smaller: `Why not smaller: ...`. PRs based on another branch (a stack) are trusted.
6. **PRs link their spec.** The PR body names the `specs/...` or `openspec/changes/...` path, or says `Spec impact: None — <why>`. That includes a placeholder body you mean to replace later.
7. **No prose comments.** Names explain the code: code and config carry no comments that explain. Bare type annotations stay (`@param list<Item> $items`, `@return array{0: int}`, `@var`, `@throws`), with nothing after the type or the variable: `@param list<Item> $items the items to keep` is prose. Tool directives (`phpcs:`, `eslint-`, `noqa`, `@ts-`, `@dataProvider`), attributes and bare markers (`@deprecated`, `@internal`) stay; `@see`, `@todo` or any tag followed by text is prose. A commit that adds prose comments is blocked. The why of a change goes in the PR, as a review comment on the line it explains, once the PR is open. After `gh pr create` the hook lists the files you had to strip, so none is forgotten.
   The one exception is a deliberate shortcut: mark it with a one-line `ponytail:` comment naming what it skips, where it stops holding, and the upgrade path (`# ponytail: global lock, per-account locks if throughput matters`).
8. **Small functions, small files.** A function reads as the list of steps it calls, each step a function whose name says what it does. Production code stays within: **15 lines per function body**, **nesting 2** (loops, conditions and closures inside a function), **4 parameters** (constructors exempt), **200 code lines per file**. Blank and comment lines do not count. Any function an edit touches must fit, legacy ones too: touch it, split it. Too many parameters means a missing object; a file over 200 lines holds more than one responsibility. A commit with code over these limits is blocked. Tests are exempt.

How to write the code:

- First ask whether it needs to exist at all. If not, skip it.
- Reuse what the repo already has, then the standard library, then the platform, before writing anything new.
- Write the shortest diff that solves the problem, but only once you understand the problem.
- Fix bugs at the cause, where every caller goes through, not at the symptom.

Never get around a block: do not write production files through Bash (`cat >`, `sed -i`, `tee`), and never create, edit or delete anything under `.git/overseer/`. The escape hatch `.git/overseer/off` belongs to the human.
