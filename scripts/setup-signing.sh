#!/bin/bash
# Creates a self-signed code-signing identity for local VimE builds, in its own keychain,
# so macOS keeps VimE's Accessibility permission across rebuilds. Safe to rerun.
set -euo pipefail

NAME="VimE Local Signing"
KEYCHAIN="$HOME/Library/Keychains/vime-signing.keychain-db"
PASS_FILE="$HOME/.config/vime/signing-keychain-password"
OPENSSL=/usr/bin/openssl  # LibreSSL: its .p12 output imports cleanly with `security`

mkdir -p "$(dirname "$PASS_FILE")"
if [ ! -f "$PASS_FILE" ]; then
  (umask 077; $OPENSSL rand -hex 24 > "$PASS_FILE")
fi
PASS="$(cat "$PASS_FILE")"

if [ ! -f "$KEYCHAIN" ]; then
  security create-keychain -p "$PASS" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"  # no auto-lock timeout
fi
security unlock-keychain -p "$PASS" "$KEYCHAIN"

# Add to the user search list (keeping what's there) so codesign can find the identity.
if ! security list-keychains -d user | grep -q "vime-signing.keychain-db"; then
  existing=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
  # shellcheck disable=SC2086
  security list-keychains -d user -s $existing "$KEYCHAIN"
fi

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Signing identity '$NAME' already exists."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
$OPENSSL pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
  -passout pass:"$PASS" -out "$tmp/identity.p12"

security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
# Lets codesign use the key without a password prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null
echo "Created signing identity '$NAME' in $KEYCHAIN"
