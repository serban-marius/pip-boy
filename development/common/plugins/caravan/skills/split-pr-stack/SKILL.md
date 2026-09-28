---
name: split-pr-stack
description: Split one big pull request into a linear stack of small PRs (each ~5 minutes of review), where every branch builds and passes its tests on its own and the top of the stack is byte-identical to the original PR. Plans the chunks, carves shared files into intermediate versions, verifies every branch, pushes once, opens the chained PRs with "Stack: phase N of M" descriptions, babysits CI and closes the original. Use it whenever the user wants to split, chunk, break up, stack or slice a PR or branch that is too big to review — "split this PR like we did in #30", "make this reviewable in 5-minute chunks", "stacked PRs", "trocea esta PR", "divide la PR", "this PR is too big" — even if they only paste a PR link and point at an earlier stack as the example.
---

# Split a PR into a reviewable stack

The goal is a chain `main ← PR1 ← PR2 ← … ← PRn` where:

- each PR is small enough to review in about five minutes (roughly 150–450 lines of
  production code; tests, fixtures and prose are skimmed faster and can make it bigger),
- each branch is **self-consistent**: it compiles, its tests pass and its linters are clean
  without the PRs above it — reviewers merge them one by one,
- the top branch equals the original PR exactly (`git diff original top` is empty), so the split
  loses and adds nothing.

The last property is the safety net for everything else: carve freely, then prove it.

## 1. Understand the original and the model to copy

- `gh pr view <n> --json title,body,headRefName,baseRefName,additions,deletions` plus
  `git diff --stat origin/<base>...<head>` for the file map, and `git log` of the branch.
- If the user points at an earlier stack as the example, read its PR bodies and
  `gh pr list --state all` to see how it was chained (base of each = previous head) and how the
  descriptions are written. Copy that format.
- Read the code you will carve — the big view, component and test files — well enough to know
  which parts depend on which. You cannot split what you have not traced.

## 2. Plan the chunks

Order by dependency, bottom first. A shape that works well:

1. **Unrelated fixes** the rest needs (a lint warning already on main that blocks the pre-push
   hook, an env/infra fix). Tiny, first, so every later push goes through.
2. **Spec / docs**, if the project keeps them — prose, read on its own.
3. **Domain model** (DTOs, value objects, enums) with its unit tests.
4. **Infrastructure adapters**, one PR per external source, dependencies before dependents
   (if repository A takes B in its constructor, B goes first). Split a big adapter by
   operation (e.g. "read the skeleton" vs "read one scope") when it is over budget.
5. **UI as vertical slices**: a shell that renders what the first read gives, then one PR per
   feature area (a section, a panel, a lazy-loaded part), each bringing its view, component
   changes and tests together.

Measure before committing to it: for each planned PR estimate code vs test lines, and split
again anything whose production code is clearly over budget. Tell the user the plan (number of
PRs, one line each) if it differs a lot from what they expect; otherwise proceed.

Put commits under the project's branch and commit conventions (check CI workflows for branch
name regexes and "spec impact"-style checks, and `git log` for the message style).

## 3. Carve intermediate versions — work backwards

Most files go into exactly one PR unchanged. The work is in the few files several PRs touch
(the page view, the component, the big test files, a shared config or provider). For those:

- Start from the final version (= PR n) and **strip the top slice** to get version n-1; strip
  the next slice from that to get n-2; and so on. Stripping is much easier than growing, and
  every version is by construction a prefix of the final one.
- Keep versions in a scratch dir mirroring repo paths (`scratch/v8/laravel/...`,
  `scratch/v7/...`), one copy per version that differs.
- Removing whole methods/tests: `bin/rm_php_methods.py <file> <name>...` removes each named
  method with its attributes and docblock (PHP classes; adapt the idea for other languages).
  Watch the class tail — removing the last method can leave a blank line before `}`.
- Exact-string edits with a small Python `edit(path, [(old, new), ...])` helper that fails when
  `old` does not match exactly once — silent no-op replacements are the typical carving bug.
- After each strip, clean what became unused: imports, properties, constants, test setup lines,
  helpers, config keys, docblocks and comments that mention the removed feature. A reviewer of
  PR k should not see traces of PR k+1.
- **Minimise test churn.** Prefer moving whole tests to the PR whose feature they test. When a
  test that belongs early asserts something from a later slice, drop just that assertion line
  early; it comes back with its feature. Renaming or rewriting tests across PRs is a last
  resort — mention it in that PR's notes when you do it.
- Interfaces grow with their implementations: add a method to the interface in the same PR as
  its implementation and first caller, or the earlier branches will not compile.

## 4. Build the branches with a script

Write one script that rebuilds the whole stack from scratch, so fixing a carve is "edit the
version, rerun":

```bash
take() { git checkout "$FINAL" -- "$@"; }                         # file as in the final PR
from() { v=$1; shift; for f; do mkdir -p "$(dirname "$f")"; cp "$S/$v/$f" "$f"; git add "$f"; done; }
br()   { git checkout -q -B "$1" "$2"; }                          # branch off the previous one
commit() { git commit -q -m "$1"; }
```

Each block: `br <name> <previous>`, `take …`, `from vK …`, `commit "<message>"`. End the script
with `git diff --stat "$FINAL" <top-branch>` — it must print nothing. If it prints anything, a
file was forgotten or a version drifted; fix it before going further.

## 5. Verify every branch on its own

Run, for **each** branch, the tests of the areas the stack touches plus the project's linters
and style checks. The point is that branch k passes without k+1, so sync that branch's tree into
the test environment and delete the files it does not have yet — otherwise a later branch's
file masks a missing piece. Look for the project's own way of running tests (Makefile,
`composer`/`npm` scripts, remote-runner scripts, CLAUDE.md).

Only push when every branch is green. If the environment is shared or slow, the full suite
once on the top branch plus targeted suites per branch is a fair trade.

## 6. Push once, open the chain, write the descriptions

- Push all branches in **one** `git push -u origin b1 b2 …`: pre-push hooks then run once,
  not n times.
- Create PRs bottom-up with `gh pr create --base <previous-branch> --head <branch>` and a
  placeholder body that already names the PR's spec path (or `Spec impact: None — <why>` for a
  tooling phase), collecting the numbers — the overseer harness blocks a PR body without one; then write the real bodies (they need the numbers)
  and apply them with `gh pr edit <n> --body-file`.
- Every body carries a **Stack** section: "Phase k of n. Based on #prev; merge that one first."
  plus the numbered list of all PRs with **this PR** marked, and a line saying the stack splits
  #original and the top leaves the code exactly as it. Then the project's usual sections (ticket,
  what it does, how to test, checklist, notes for reviewer) scoped to this slice only: what is
  new here, where to look hardest, what comes later in the stack.
- The top PR's body states the invariant with the command that proves it
  (`git diff origin/<original-head> origin/<top-head>` is empty).

## 7. Babysit CI

Opening n PRs at once starts n pipelines together, and anything shared will contend:
Terraform state locks ("Error acquiring the state lock"), deployment/promotion systems that
cannot find an image yet, rate limits. These are not code failures:

- Read the failing job's log before deciding (`gh api repos/<o>/<r>/actions/jobs/<id>/logs
  --allow-escape-sequences`).
- Rerun contention failures **one at a time**, and only once the run has completed — a job
  cannot be rerun while its run is still in progress. A background loop that waits for each run
  to complete, runs `gh run rerun <run> --failed`, and waits again works well.
- If a failure also happens on the original PR, it is not caused by the split: say so, show
  the evidence, and ask before fixing it — especially if the fix touches files owned by a
  shared base or framework.

## 8. Close the original — ask first

Do not close the original PR on your own. When the user agrees, close it with a comment that
lists the stack in merge order and states the diff-is-empty invariant. Keep its branch unless
asked: it is the reference the invariant is checked against.

## Report back

End with a table (PR, one-line scope, code/total lines), the verification done per branch, the
CI state per PR with the reason for any red, and the open decisions for the user.

## Project-specific notes

- Softonic laravel-base projects (Toucan etc.: `remotePHP`, `make intern` pods, pre-push hook,
  Terraform plan per PR): read `references/laravel-base.md`.
