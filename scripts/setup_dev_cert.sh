#!/bin/bash
#
# Create a stable self-signed code-signing certificate for TeXtUtility so its
# Accessibility grant survives rebuilds. macOS keys TCC entries by the
# binary's code-signing "designated requirement"; ad-hoc signatures change
# every build, which invalidates the grant. Signing with a fixed cert keeps
# the DR stable across rebuilds.
#
# Run this ONCE. Idempotent — safe to re-run; it skips work if the cert
# already exists.
#
set -euo pipefail

CERT_NAME="TeXtUtility Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BUNDLE_ID="com.local.textutility"

# 1. Already in the keychain? Nothing to do. (Use no -v so we find untrusted
# self-signed certs too; that's what we install here.)
EXISTING_COUNT=$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -c "\"$CERT_NAME\"" || true)
if [ "$EXISTING_COUNT" -ge 1 ]; then
    echo "cert '$CERT_NAME' is already installed ($EXISTING_COUNT cop$([ "$EXISTING_COUNT" -eq 1 ] && echo "y" || echo "ies"))."
    if [ "$EXISTING_COUNT" -gt 1 ]; then
        echo "  multiple copies will make codesign ambiguous. delete with:"
        security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | \
            awk -v name="\"$CERT_NAME\"" '$0 ~ name {print "    security delete-identity -Z " $2 " " ENVIRON["HOME"] "/Library/Keychains/login.keychain-db"}'
    fi
    exit 0
fi

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo "creating self-signed code-signing cert: $CERT_NAME"

# 2. Generate cert + key with the extensions codesign needs.
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
[req_dn]
CN = $CERT_NAME
EOF

# Prefer macOS's bundled LibreSSL — its defaults (3DES + SHA1) match what
# `security import` accepts. Fall back to whatever `openssl` is on PATH
# (Homebrew openssl 3 needs -legacy to produce an importable archive).
OPENSSL="/usr/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl)"
LEGACY_FLAG=""
if "$OPENSSL" pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    LEGACY_FLAG="-legacy"
fi

"$OPENSSL" req -new -x509 -nodes -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -config "$TMP/cert.cnf" \
    -addext "basicConstraints = critical, CA:false" \
    -addext "keyUsage = critical, digitalSignature" \
    -addext "extendedKeyUsage = critical, codeSigning" \
    >/dev/null 2>&1

# `security import` rejects PKCS12 archives encrypted with an empty
# password — it fails MAC verification regardless of algorithm. Use a real
# password and pass it through to `security import`. The password only
# protects the on-disk .p12 (which we delete) so its value is just plumbing.
P12_PASSWORD="setup"
"$OPENSSL" pkcs12 -export -out "$TMP/cert.p12" $LEGACY_FLAG \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -passout "pass:$P12_PASSWORD" \
    >/dev/null 2>&1

# 3. Import to login keychain. -T /usr/bin/codesign permits codesign to use
# the private key without re-prompting. The keychain itself may prompt for
# your login password the first time.
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    >/dev/null

# 4. (Optional) Mark the cert as system-trusted. Not required for codesign
# to use the cert and not required for TCC to remember the grant — TCC keys
# on the binary's designated requirement, which references the cert by hash
# regardless of trust. Trusting it only matters if you ever want Gatekeeper
# to consider the binary "signed by a known authority". We skip it by
# default because it requires sudo and isn't load-bearing.
if [ "${TRUST_CERT:-0}" = "1" ]; then
    echo "marking cert as trusted for code signing (sudo required)..."
    sudo security add-trusted-cert -d -r trustRoot \
        -p codeSign \
        -k /Library/Keychains/System.keychain \
        "$TMP/cert.pem" || \
        echo "  (trust step failed — not fatal, codesign will still work)"
fi

# 5. Reset any prior TCC grant for this bundle id so the next launch can
# attach a grant to the new (stable) signature instead of the old ad-hoc one.
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo
echo "done. next steps:"
echo "  1. ./scripts/build_app.sh   # rebuild + reinstall, signed with the new cert"
echo "  2. open ~/Applications/TeXtUtility.app  # launch — it'll prompt for Accessibility once"
echo "  3. enable TeXtUtility in System Settings → Privacy & Security → Accessibility"
echo
echo "subsequent rebuilds will preserve the grant (DR stays stable across builds)."
