#!/bin/bash
# Draws the app icon at every size macOS wants and packs it into VimE/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
swift scripts/make-icon.swift "$SET"
iconutil -c icns "$SET" -o VimE/AppIcon.icns
rm -rf "$(dirname "$SET")"
echo VimE/AppIcon.icns
