#!/bin/bash
# Creates a self-signed code-signing certificate in your login keychain.
# build.sh signs with it when present, so macOS keeps Keytalk's Accessibility
# permission across rebuilds.
#
# Usage: scripts/make-signing-cert.sh [NAME]
#   NAME defaults to "Keytalk Local Signing". Maintainers create
#   "Keytalk Release Signing" once and sign every release with it.
set -euo pipefail

NAME="${1:-Keytalk Local Signing}"
if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
  echo "'$NAME' already exists in your keychain."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

PASS=$(openssl rand -hex 16)
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg.cnf" 2>/dev/null
# -legacy: macOS cannot read the PKCS#12 encryption that OpenSSL 3 uses by
# default. LibreSSL (the /usr/bin/openssl that ships with macOS) has no such
# flag and already writes the old format.
LEGACY=$(openssl version | grep -q '^OpenSSL 3' && echo -legacy || true)
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "$PASS" -T /usr/bin/codesign

echo "Created '$NAME'. Run ./build.sh to sign Keytalk with it."
