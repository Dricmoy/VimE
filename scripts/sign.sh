#!/bin/bash
# Re-signs a built VimE.app with the local identity from setup-signing.sh.
# A stable signature is what lets macOS remember the Accessibility permission across builds.
# Releases set VIME_SIGN_IDENTITY, VIME_SIGN_KEYCHAIN and VIME_SIGN_PASS_FILE (scripts/import-release-signing.sh)
# and VIME_SIGN_REQUIRED=1, so a release can never go out ad-hoc signed.
set -euo pipefail

APP="$1"
NAME="${VIME_SIGN_IDENTITY:-VimE Local Signing}"
KEYCHAIN="${VIME_SIGN_KEYCHAIN:-$HOME/Library/Keychains/vime-signing.keychain-db}"
PASS_FILE="${VIME_SIGN_PASS_FILE:-$HOME/.config/vime/signing-keychain-password}"

if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASS_FILE" ]; then
  if [ "${VIME_SIGN_REQUIRED:-0}" = 1 ]; then
    echo "error: signing identity '$NAME' not found" >&2
    exit 1
  fi
  echo "warning: no local signing identity; VimE stays ad-hoc signed. Run: make signing" >&2
  exit 0
fi
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KEYCHAIN"

# --options runtime keeps the hardened runtime that Xcode's own signature had.
sign() { codesign --force --options runtime --sign "$NAME" --keychain "$KEYCHAIN" "$1" 2>&1 | grep -v "replacing existing signature" || true; }
# Inside out: nested code first, the app bundle last.
for fw in "$APP"/Contents/Frameworks/*.framework; do [ -e "$fw" ] && sign "$fw"; done
for lib in "$APP"/Contents/MacOS/*.dylib; do [ -e "$lib" ] && sign "$lib"; done
sign "$APP"
codesign --verify --deep --strict "$APP"
