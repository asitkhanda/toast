#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Toast"
EXECUTABLE_NAME="Toast"
LAUNCHER_NAME="ToastLauncher"
BUNDLE_ID="com.toast.app"
LAUNCHER_BUNDLE_ID="com.toast.app.launcher"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Resources/Toast.entitlements"
ADHOC_ENTITLEMENTS="$ROOT/Resources/Toast.adhoc.entitlements"
INFO_PLIST="$ROOT/Resources/Info.plist"
LAUNCHER_INFO_PLIST="$ROOT/Resources/ToastLauncher-Info.plist"
ICON_SOURCE="$ROOT/Resources/toast.icon"
ICON_NAME="toast"

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION="$(read_plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(read_plist_value CFBundleVersion)"
ZIP_NAME="Toast-${VERSION}.zip"
ZIP_PATH="$ROOT/dist/$ZIP_NAME"
DMG_NAME="Toast-${VERSION}.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
NOTARIZE_STATE="$ROOT/dist/${APP_NAME}.app.notarize-state"

should_resume_notarization() {
    [[ "${NOTARIZE:-}" == "1" ]] || return 1
    [[ -d "$APP_DIR" ]] || return 1
    [[ -f "$NOTARIZE_STATE" ]] || return 1
    local status
    status="$(grep "^STATUS=" "$NOTARIZE_STATE" 2>/dev/null | cut -d= -f2- || true)"
    # Don't rebuild while waiting on Apple or while ticket still needs stapling.
    # Rebuilding changes the binary and invalidates the accepted submission.
    [[ "$status" == "in_progress" || "$status" == "accepted" ]]
}

if should_resume_notarization; then
    echo "Found in-progress notarization for $APP_NAME.app — skipping rebuild to avoid duplicate submission."
    echo "Will resume polling Apple and continue with DMG once accepted."
else
    echo "Building Toast (release)..."
    cd "$ROOT"
    swift package resolve
    swift build -c release

    echo "Generating dSYM..."
    DSYM_PATH="$ROOT/dist/Toast.dSYM"
    rm -rf "$DSYM_PATH"
    dsymutil "$BUILD_DIR/$EXECUTABLE_NAME" -o "$DSYM_PATH"

    echo "Packaging $APP_NAME.app..."
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS"
    mkdir -p "$APP_DIR/Contents/Frameworks"
    mkdir -p "$APP_DIR/Contents/Resources"

    cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
    cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
    chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

    LAUNCHER_APP_DIR="$APP_DIR/Contents/Library/LoginItems/ToastLauncher.app"
    mkdir -p "$LAUNCHER_APP_DIR/Contents/MacOS"
    cp "$BUILD_DIR/$LAUNCHER_NAME" "$LAUNCHER_APP_DIR/Contents/MacOS/$LAUNCHER_NAME"
    cp "$LAUNCHER_INFO_PLIST" "$LAUNCHER_APP_DIR/Contents/Info.plist"
    chmod +x "$LAUNCHER_APP_DIR/Contents/MacOS/$LAUNCHER_NAME"

    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $LAUNCHER_BUNDLE_ID" "$LAUNCHER_APP_DIR/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $LAUNCHER_BUNDLE_ID" "$LAUNCHER_APP_DIR/Contents/Info.plist"

    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

    echo "Compiling app icon..."
    ICON_BUILD_DIR="$ROOT/dist/icon-build"
    ICON_INFO_PLIST="$ROOT/dist/icon-info.plist"
    rm -rf "$ICON_BUILD_DIR"
    mkdir -p "$ICON_BUILD_DIR"
    if ! xcrun actool "$ICON_SOURCE" \
        --compile "$ICON_BUILD_DIR" \
        --app-icon "$ICON_NAME" \
        --output-partial-info-plist "$ICON_INFO_PLIST" \
        --include-all-app-icons \
        --target-device mac \
        --minimum-deployment-target 14.0 \
        --platform macosx; then
        echo "Error: actool failed to compile $ICON_SOURCE"
        exit 1
    fi
    if [ ! -f "$ICON_BUILD_DIR/Assets.car" ] || [ ! -f "$ICON_BUILD_DIR/${ICON_NAME}.icns" ]; then
        echo "Error: actool did not produce Assets.car and ${ICON_NAME}.icns"
        exit 1
    fi
    cp "$ICON_BUILD_DIR/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
    cp "$ICON_BUILD_DIR/${ICON_NAME}.icns" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
    rm -rf "$ICON_BUILD_DIR" "$ICON_INFO_PLIST"

    echo "Embedding Sparkle.framework..."
    SPARKLE_FW="$(find "$ROOT/.build/artifacts" -name "Sparkle.framework" -maxdepth 6 | head -1)"
    if [ -z "$SPARKLE_FW" ]; then
        echo "Error: Sparkle.framework not found in .build/artifacts — run 'swift package resolve' first"
        exit 1
    fi
    cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"

    # Non-sandboxed apps should remove Sparkle XPC services to avoid installer launch failures.
    rm -rf "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
    rm -f "$APP_DIR/Contents/Frameworks/Sparkle.framework/XPCServices"

    install_name_tool \
        -add_rpath "@executable_path/../Frameworks" \
        "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true

    chmod +x "$ROOT/scripts/codesign-app.sh"
    if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        echo "Signing (Developer ID)..."
        "$ROOT/scripts/codesign-app.sh" "$APP_DIR" "$SIGN_IDENTITY" "$ENTITLEMENTS"
    else
        echo "Signing (ad-hoc — set SIGN_IDENTITY for Developer ID builds)..."
        codesign --force --deep --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"
        codesign --force --sign - --options runtime "$LAUNCHER_APP_DIR"
        codesign --force --deep --sign - --entitlements "$ADHOC_ENTITLEMENTS" --options runtime "$APP_DIR"
    fi
fi

if [[ "${NOTARIZE:-}" == "1" ]]; then
    if [[ -z "${SIGN_IDENTITY:-}" ]]; then
        echo "Error: NOTARIZE=1 requires SIGN_IDENTITY."
        exit 1
    fi
    chmod +x "$ROOT/scripts/notarize.sh"
    "$ROOT/scripts/notarize.sh" "$APP_DIR"
fi

echo "Refreshing DMG backgrounds..."
swift "$ROOT/scripts/generate-dmg-background.swift" \
    "$ROOT/Resources/dmg-background.png" \
    "$ROOT/Resources/dmg-background@2x.png"

echo "Creating $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Creating $DMG_NAME..."
# Styled installer DMG with Gatekeeper checkpoints (falls back to plain DMG in CI).
chmod +x "$ROOT/scripts/package-dmg.sh"
"$ROOT/scripts/package-dmg.sh" "$APP_DIR" "$DMG_PATH"

if [[ "${NOTARIZE:-}" == "1" ]]; then
    "$ROOT/scripts/notarize.sh" "$DMG_PATH"
fi

echo "Built: $APP_DIR"
echo "Install: $DMG_PATH"
echo "Update archive: $ZIP_PATH"
echo ""
echo "Run with:"
echo "  open \"$APP_DIR\""
