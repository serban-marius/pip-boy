# Caravan

A caravan crosses the Wasteland as a line of small wagons, each one carrying its own load and hitched to the one ahead. Here the wagons are pull requests.

## Skills

### split-pr-stack

Split one PR that is too big to review into a linear stack (`main ← PR1 ← PR2 ← … ← PRn`) of chunks of about five minutes of review each.

- **Plans** the chunks bottom-up: unrelated fixes that unblock hooks, spec, domain, one adapter per external source, then the UI as vertical slices.
- **Carves** the files several PRs share by working backwards from the final version, stripping one slice at a time, with minimal test churn.
- **Builds** every branch from one rebuild script and checks the invariant: the top branch is identical to the original PR.
- **Verifies** each branch on its own (tests of the touched areas, linters) before anything is pushed.
- **Ships** with one push, chained PRs (`--base` = previous branch) and "Stack: phase k of n" descriptions.
- **Babysits CI**: shared-resource contention (Terraform state locks, deploy freight) is rerun one run at a time; failures that the original PR also has are reported, not silently "fixed".
- **Asks** before closing the original PR, then closes it with the stack in merge order.

`references/laravel-base.md` holds the Softonic laravel-base specifics (intern pod sync, CI conventions, known CI contention). `bin/rm_php_methods.py` removes whole methods from a PHP class while carving.

**Usage:** "split this PR like we did in #30", "make #101 reviewable in 5-minute chunks", "stack this branch", "trocea esta PR".

**Requirements:** `gh` authenticated against the repo, and a way to run the project's tests per branch.
