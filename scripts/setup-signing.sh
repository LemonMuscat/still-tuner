#!/bin/bash
# Create a persistent app identity, with code-signing-only trust in the user domain.
set -euo pipefail
SIGNING_DIR="$HOME/Library/Application Support/StillTuner/Signing"
KEYCHAIN="$SIGNING_DIR/still-tuner.keychain-db"
umask 077
mkdir -p "$SIGNING_DIR"
if [[ -f "$KEYCHAIN" ]]; then
    echo "Still Tuner signing keychain already exists."
    exit 0
fi
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
openssl rand -hex 32 > "$SIGNING_DIR/keychain-password"
openssl rand -hex 32 > "$TEMP_DIR/import-password"
cat > "$TEMP_DIR/cert.conf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Still Tuner Local Signing
[ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CONF
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 -config "$TEMP_DIR/cert.conf" -keyout "$TEMP_DIR/private.pem" -out "$SIGNING_DIR/certificate.pem" 2> "$TEMP_DIR/openssl.log"
openssl pkcs12 -export -inkey "$TEMP_DIR/private.pem" -in "$SIGNING_DIR/certificate.pem" -name 'Still Tuner Local Signing' -out "$TEMP_DIR/identity.p12" -passout "file:$TEMP_DIR/import-password"
security create-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$KEYCHAIN"
security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$KEYCHAIN"
security import "$TEMP_DIR/identity.p12" -k "$KEYCHAIN" -P "$(cat "$TEMP_DIR/import-password")" -T /usr/bin/codesign
openssl x509 -in "$SIGNING_DIR/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' > "$SIGNING_DIR/identity-sha1"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$SIGNING_DIR/certificate.pem"
echo "Created app signing identity with user code-signing trust. Privacy permissions were not modified."
