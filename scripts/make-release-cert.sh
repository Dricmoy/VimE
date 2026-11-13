#!/bin/bash
# Maintainer, once: creates the "VimE Release Signing" identity that CI signs every release with and stores it
# as the RELEASE_CERT_P12 / RELEASE_CERT_PASSWORD secrets of the GitHub repo. macOS ties the Accessibility
# permission to this certificate, so replacing it makes every user grant access again: keep the backup safe.
set -euo pipefail

NAME="VimE Release Signing"
DIR="$HOME/.config/vime"
P12="$DIR/release-signing.p12"
PASS_FILE="$DIR/release-signing-password"
OPENSSL=/usr/bin/openssl  # LibreSSL: its .p12 output imports cleanly with `security`

if [ -f "$P12" ]; then
  echo "$P12 already exists. Re-uploading it instead of making a new one."
else
  mkdir -p "$DIR"
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
  $OPENSSL req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  (umask 077; $OPENSSL rand -hex 24 > "$PASS_FILE")
  (umask 077; $OPENSSL pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -passout file:"$PASS_FILE" -out "$P12")
  echo "Created $P12"
fi

base64 < "$P12" | gh secret set RELEASE_CERT_P12
tr -d "\n" < "$PASS_FILE" | gh secret set RELEASE_CERT_PASSWORD
echo "Uploaded RELEASE_CERT_P12 and RELEASE_CERT_PASSWORD. Back up $P12 and $PASS_FILE (e.g. in a password manager)."
