#!/bin/bash
# Create a self-signed code signing identity so keychain grants survive rebuilds.
#
# An ad-hoc signature has no stable designated requirement, so macOS pins every keychain
# "Always Allow" to the exact build hash and re-prompts after the next build. A self-signed
# certificate gives the app a durable identity, and one grant then holds indefinitely.

set -e

IDENTITY="${CLAUDEUSAGE_SIGN_IDENTITY:-ClaudeUsage Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists. Nothing to do."
    exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/openssl.cnf" << CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $IDENTITY

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# Use the system LibreSSL, not a homebrew OpenSSL 3: its PKCS#12 defaults (AES-256 + SHA-256 MAC)
# are rejected by Security.framework on import.
OPENSSL=/usr/bin/openssl
P12_PASSWORD=$(uuidgen)

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$WORKDIR/openssl.cnf" \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" 2>/dev/null

"$OPENSSL" pkcs12 -export -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/identity.p12" -passout "pass:$P12_PASSWORD"

echo "Importing '$IDENTITY' into the login keychain (you may be asked to allow access)..."
security import "$WORKDIR/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security

# Let codesign use the private key without a prompt on every build.
security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN" > /dev/null 2>&1 || true

echo "Trusting '$IDENTITY' for code signing (this asks for your login password)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo
security find-identity -v -p codesigning | grep -F "$IDENTITY"
echo
echo "Done. Run ./build.sh and it will sign with this identity."
echo "The next keychain prompt you approve with Always Allow will survive future rebuilds."
