# PR Janitor

Maintain the current author's open pull requests without creating review noise.

The skill refreshes the pull request before every mutation, proves that each CI failure or review finding still applies to the latest head, makes minimal verified fixes, and reports direct pull request links.

## Safety rules

- All commits, GitHub replies, and reports are written in English.
- Fixed, stale, outdated, duplicate, resolved, non-reproducible, or superseded findings receive no code change and no reply.
- Human-authored review threads are never resolved by the skill.
- Bot-authored threads may be resolved only after the fix is verified on the latest head.
- The skill never merges, closes, relabels, or force-pushes.

## Usage

Invoke `/pr-janitor` with a pull request URL, repository, or explicit scope. It can also be used by an authorized scheduled run limited to pull requests authored by the configured GitHub identity.

Examples:

- `/pr-janitor https://github.com/example/project/pull/42`
- `Keep my open ready-for-review PRs green and handle actionable review feedback.`

## Requirements

- Git and GitHub CLI (`gh`)
- Authenticated GitHub access with permission to update the selected pull request branches
