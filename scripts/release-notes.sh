#!/bin/bash
# Prints the CHANGELOG.md section for one version, plus install instructions, as GitHub release notes.
set -euo pipefail
VERSION="$1"
cd "$(dirname "$0")/.."

notes=$(awk -v v="$VERSION" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' CHANGELOG.md | sed -e '/./,$!d')
if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
  echo "error: CHANGELOG.md has no notes for $VERSION" >&2
  exit 1
fi
printf '%s\n' "$notes"
cat <<MD

---

**Install:** \`brew tap dricmoy/tap && brew trust --cask dricmoy/tap/vime && brew install --cask dricmoy/tap/vime\`, or download \`VimE-$VERSION.dmg\` below. **Update:** \`brew upgrade --cask vime\`.

VimE isn't notarized by Apple yet, so macOS blocks the first launch of each new version: open it once, then allow it in System Settings → Privacy & Security → Open Anyway. The Accessibility permission carries over between releases.
MD
