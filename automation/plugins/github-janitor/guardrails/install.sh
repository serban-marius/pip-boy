#!/usr/bin/env bash
# Install the gh/git guardrail shims on a Debian/Ubuntu host (needs sudo).
# The real binaries are diverted to /usr/bin/gh.real and /usr/bin/git.real with
# dpkg-divert, so apt upgrades keep the shims in place. Idempotent; re-run to update.
# Usage: guardrails/install.sh        (then test-shims.sh runs automatically)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v dpkg-divert >/dev/null || { echo "dpkg-divert not found: this installer is for Debian-based hosts" >&2; exit 1; }
for b in gh git; do
  [ -x "/usr/bin/$b" ] || [ -x "/usr/bin/$b.real" ] || { echo "/usr/bin/$b not found; install $b with apt first" >&2; exit 1; }
  sudo dpkg-divert --add --rename --divert "/usr/bin/$b.real" "/usr/bin/$b" >/dev/null
  sudo install -m 755 "$here/$b" "/usr/bin/$b"
done
bash "$here/test-shims.sh"
