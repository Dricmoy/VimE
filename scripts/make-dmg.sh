#!/bin/bash
# Packs VimE.app into a compressed disk image with an Applications shortcut to drag onto.
set -euo pipefail

APP="$1"
OUT="$2"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/VimE.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname VimE -srcfolder "$STAGE" -fs HFS+ -format UDZO "$OUT"
echo "$OUT"
