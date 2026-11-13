#!/bin/bash
# Maintainer: make release V=1.2.3. Turns CHANGELOG.md's Unreleased section into this version, sets the
# version in project.yml, commits, tags v1.2.3 and pushes. GitHub Actions then builds, signs and publishes
# the release and updates the Homebrew cask (.github/workflows/release.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:-}"

[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "usage: make release V=1.2.3" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "error: release from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "error: commit or stash your changes first" >&2; exit 1; }
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "error: main isn't in sync with origin/main" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/v$V" >/dev/null || { echo "error: v$V already exists" >&2; exit 1; }

unreleased=$(awk 'index($0, "## [Unreleased]") == 1 { on = 1; next } on && /^## \[/ { exit } on { print }' CHANGELOG.md)
[ -n "$(printf '%s' "$unreleased" | tr -d '[:space:]')" ] || {
  echo "error: add what changed under '## [Unreleased]' in CHANGELOG.md first" >&2; exit 1; }

today=$(date +%Y-%m-%d)
awk -v v="$V" -v d="$today" '
  index($0, "## [Unreleased]") == 1 && !done { print; print ""; print "## [" v "] - " d; done = 1; next }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
sed -i '' -E "s/^( *MARKETING_VERSION: )\".*\"/\1\"$V\"/" project.yml

scripts/release-notes.sh "$V" >/dev/null
git add CHANGELOG.md project.yml
git commit --quiet -m "Release $V"
git tag -a "v$V" -m "VimE $V"
git push --quiet origin main "v$V"
echo "Pushed v$V. Watch the build: https://github.com/Dricmoy/VimE/actions"
