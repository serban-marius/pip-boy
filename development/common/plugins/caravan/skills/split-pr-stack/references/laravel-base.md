# Splitting PRs in Softonic laravel-base projects

What made the DS-3650 split (toucan #101 → #103…#113) work, and what cost time.

## Verifying a branch in the intern/dev pod

- `laravel/core/bin/detectEnvironment` gives `REMOTE_PHP_CONTEXT` / `REMOTE_PHP_NAMESPACE`.
  From macOS export `PATH="/opt/homebrew/bin:$PATH" LC_ALL=C` first (bash ≥ 5, BSD sed).
- An intern pod does not mount the checkout. Per branch: for every `laravel/` path the original
  PR touches, `git show <branch>:laravel/<path>` into a temp dir if the branch has it, else
  collect it for deletion; tar the dir into the pod
  (`COPYFILE_DISABLE=1 tar --no-xattrs -cf - . | kubectl exec -i <server-pod> -c php-fpm -- tar -xf - -C /opt/app`)
  and `rm -f` the absent ones. Then `php artisan view:clear`.
- Pick the pod by name (`toucan-server-*`), not by label — the cli-helper label matched several pods.
- Run with `vendor/bin/phpunit --no-progress --colors=never --no-coverage <dir>`; without
  `--colors=never` the `OK (...)` line carries ANSI codes and greps miss it.
- Per branch: the touched suites (`tests/Unit/Pages/<Page>`, `tests/Feature/Pages/<Page>`, any
  integration test the stack edits), `vendor/bin/pint --test <app files>`, and
  `vendor/bin/phpmd <app dirs> text phpmd_ruleset.xml`.
- Pint does not run on `tests/`; PHPMD excludes `app/Providers/*`.

## Conventions the CI checks

- Branch names: `^(feature|fix|refactor|chore|docs|test|hotfix)/[A-Z][A-Z0-9]*-[0-9]+-[a-z0-9-]+$`.
- Spec impact (advisory): `feature|fix|refactor` branches need a `specs/NNN-*/spec.md|research.md`
  change **in their own diff** or a `Spec impact: None — <category>` line. With the spec in its
  own `docs/` PR, the feature PRs of the stack will warn; state in each body that it implements
  the spec shipped in #<spec PR>.
- Commit/PR titles: `type(scope): #KEY-123 lowercase summary`.

## CI contention after opening the stack

- "Terraform Plan" takes `gs://terraform-state-kubertonic/<slug>/production.tflock`: most
  plans of the batch fail on the lock. Rerun sequentially after each run completes.
- "Run CI tests" (Kargo) can fail with `Freight with image <sha> not found after warehouse
  refresh` when many images land together — rerun.
- The coverage unit run is one PHP process with a 128 MB limit; a PR that adds many Livewire
  tests can hit `Allowed memory size ... exhausted` / "Premature end of PHP process". Check
  whether the original PR fails the same way before blaming the split. `phpunit.xml` and the base
  scripts in `composer.json` are shared with laravel-base — ask before changing them.

## Files not to carve blindly

- `laravel/core/`, `docs/laravel/`, non-`.app` helm values: laravel-base owned, never edit.
- `AppServiceProvider`, `config/*.php`, helm `*.app.yaml`: often touched by several slices —
  carve them like the view (backwards from the final version).
