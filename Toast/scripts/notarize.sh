#!/usr/bin/env bash
# Submit a .app or .dmg to Apple notarization and staple the ticket.
set -euo pipefail

ARTIFACT="${1:?Usage: notarize.sh <Toast.app|Toast.dmg>}"
ARTIFACT="$(cd "$(dirname "$ARTIFACT")" && pwd)/$(basename "$ARTIFACT")"

if [[ ! -e "$ARTIFACT" ]]; then
    echo "Error: artifact not found at $ARTIFACT"
    exit 1
fi

SUBMIT_ZIP=""
cleanup() {
    if [[ -n "$SUBMIT_ZIP" && -f "$SUBMIT_ZIP" ]]; then
        rm -f "$SUBMIT_ZIP"
    fi
}
trap cleanup EXIT

submit_args=()
if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
    submit_args=(
        --key "$APPLE_API_KEY_PATH"
        --key-id "$APPLE_API_KEY_ID"
        --issuer "$APPLE_API_ISSUER_ID"
    )
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_NOTARIZATION_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    submit_args=(
        --apple-id "$APPLE_ID"
        --password "$APPLE_NOTARIZATION_PASSWORD"
        --team-id "$APPLE_TEAM_ID"
    )
else
    echo "Error: notarization credentials are not configured."
    echo "Set APPLE_API_KEY_PATH, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID"
    echo "or APPLE_ID, APPLE_NOTARIZATION_PASSWORD, APPLE_TEAM_ID."
    exit 1
fi

if [[ "$ARTIFACT" == *.app ]]; then
    SUBMIT_ZIP="$(mktemp -t toast-notarize).zip"
    echo "Creating notarization archive for app..."
    ditto -c -k --keepParent "$ARTIFACT" "$SUBMIT_ZIP"
    SUBMIT_PATH="$SUBMIT_ZIP"
else
    SUBMIT_PATH="$ARTIFACT"
fi

echo "Submitting $(basename "$ARTIFACT") for notarization..."
xcrun notarytool submit "$SUBMIT_PATH" "${submit_args[@]}" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"

echo "Notarized: $ARTIFACT"
