#!/usr/bin/env bash
# Sign Toast.app and embedded helpers with a Developer ID (or other) identity.
set -euo pipefail

APP_DIR="${1:?Usage: codesign-app.sh <Toast.app> <signing-identity> [entitlements.plist]}"
SIGN_IDENTITY="${2:?Usage: codesign-app.sh <Toast.app> <signing-identity> [entitlements.plist]}"
ENTITLEMENTS="${3:-}"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Error: app bundle not found at $APP_DIR"
    exit 1
fi

sign() {
    local target="$1"
    shift
    if [[ ! -e "$target" ]]; then
        return 0
    fi
    echo "  codesign: ${target#$APP_DIR/}"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@" "$target"
}

echo "Signing with identity: $SIGN_IDENTITY"

SPARKLE_FW="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    while IFS= read -r -d '' helper; do
        sign "$helper"
    done < <(find "$SPARKLE_FW" -depth \( -name "*.app" -o -name "Autoupdate" -o -name "*.xpc" \) -print0)
    sign "$SPARKLE_FW"
fi

LAUNCHER_APP="$APP_DIR/Contents/Library/LoginItems/ToastLauncher.app"
sign "$LAUNCHER_APP"

MAIN_EXECUTABLE="$APP_DIR/Contents/MacOS/Toast"
if [[ -f "$MAIN_EXECUTABLE" ]]; then
    if [[ -n "$ENTITLEMENTS" ]]; then
        sign "$MAIN_EXECUTABLE" --entitlements "$ENTITLEMENTS"
    else
        sign "$MAIN_EXECUTABLE"
    fi
fi

if [[ -n "$ENTITLEMENTS" ]]; then
    sign "$APP_DIR" --entitlements "$ENTITLEMENTS"
else
    sign "$APP_DIR"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR" || true
