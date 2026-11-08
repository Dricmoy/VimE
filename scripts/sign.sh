#!/bin/bash
# Re-signs a built VimE.app with the local identity from setup-signing.sh.
# A stable signature is what lets macOS remember the Accessibility permission across builds.
set -euo pipefail

APP="$1"
NAME="VimE Local Signing"
KEYCHAIN="$HOME/Library/Keychains/vime-signing.keychain-db"
PASS_FILE="$HOME/.config/vime/signing-keychain-password"

if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASS_FILE" ]; then
  echo "warning: no local signing identity; VimE stays ad-hoc signed. Run: make signing" >&2
  exit 0
fi
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KEYCHAIN"

sign() { codesign --force --sign "$NAME" --keychain "$KEYCHAIN" "$1" 2>&1 | grep -v "replacing existing signature" || true; }
# Inside out: nested code first, the app bundle last.
for fw in "$APP"/Contents/Frameworks/*.framework; do [ -e "$fw" ] && sign "$fw"; done
for lib in "$APP"/Contents/MacOS/*.dylib; do [ -e "$lib" ] && sign "$lib"; done
sign "$APP"
codesign --verify --deep --strict "$APP"
