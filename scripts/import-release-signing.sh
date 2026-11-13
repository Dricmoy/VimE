#!/bin/bash
# CI only: puts the release signing identity (the RELEASE_CERT_P12 and RELEASE_CERT_PASSWORD secrets) in a
# throwaway keychain and points scripts/sign.sh at it for the rest of the job.
set -euo pipefail
: "${RELEASE_CERT_P12:?RELEASE_CERT_P12 secret missing}" "${RELEASE_CERT_PASSWORD:?RELEASE_CERT_PASSWORD secret missing}"

DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$DIR/vime-release.keychain-db"
PASS_FILE="$DIR/vime-release-keychain-password"
(umask 077; /usr/bin/openssl rand -hex 24 > "$PASS_FILE")
PASS="$(cat "$PASS_FILE")"

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"  # no auto-lock during the build
security unlock-keychain -p "$PASS" "$KEYCHAIN"
(umask 077; printf '%s' "$RELEASE_CERT_P12" | base64 --decode > "$DIR/release.p12")
security import "$DIR/release.p12" -k "$KEYCHAIN" -P "$RELEASE_CERT_PASSWORD" -T /usr/bin/codesign
rm -f "$DIR/release.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null
existing=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $existing

{
  echo "VIME_SIGN_IDENTITY=VimE Release Signing"
  echo "VIME_SIGN_KEYCHAIN=$KEYCHAIN"
  echo "VIME_SIGN_PASS_FILE=$PASS_FILE"
  echo "VIME_SIGN_REQUIRED=1"
} >> "${GITHUB_ENV:-/dev/stdout}"
