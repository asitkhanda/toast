#!/usr/bin/env bash
# Import a Developer ID .p12 into a temporary CI keychain.
set -euo pipefail

if [[ -z "${APPLE_CERTIFICATE_P12:-}" || -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]]; then
    echo "Error: APPLE_CERTIFICATE_P12 and APPLE_CERTIFICATE_PASSWORD must be set."
    exit 1
fi

KEYCHAIN="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
CERT_PATH="$RUNNER_TEMP/apple-certificate.p12"

if base64 --decode </dev/null >/dev/null 2>&1; then
    echo "$APPLE_CERTIFICATE_P12" | base64 --decode > "$CERT_PATH"
else
    echo "$APPLE_CERTIFICATE_P12" | base64 -D > "$CERT_PATH"
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERT_PATH" \
    -P "$APPLE_CERTIFICATE_PASSWORD" \
    -A \
    -t cert \
    -f pkcs12 \
    -k "$KEYCHAIN" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/xcrun
security list-keychain -d user -s "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "Error: could not find a Developer ID Application identity in the imported certificate."
        security find-identity -v -p codesigning "$KEYCHAIN" || true
        exit 1
    fi
    echo "SIGN_IDENTITY=$SIGN_IDENTITY" >> "$GITHUB_ENV"
fi

echo "Imported signing certificate into $KEYCHAIN"
