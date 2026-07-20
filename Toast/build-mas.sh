#!/usr/bin/env bash
# Build Toast for Mac App Store submission (sandboxed, no Sparkle).
set -euo pipefail

export APPSTORE=1

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Toast"
EXECUTABLE_NAME="Toast"
LAUNCHER_NAME="ToastLauncher"
BUNDLE_ID="com.toast.app"
LAUNCHER_BUNDLE_ID="com.toast.app.launcher"
BUILD_DIR="$ROOT/.build/release"
DIST_DIR="$ROOT/dist/mas"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Resources/Toast.mas.entitlements"
LAUNCHER_ENTITLEMENTS="$ROOT/Resources/ToastLauncher.mas.entitlements"
INFO_PLIST="$ROOT/Resources/Info.plist"
LAUNCHER_INFO_PLIST="$ROOT/Resources/ToastLauncher-Info.plist"
ICON_SOURCE="$ROOT/Resources/toast.icon"
ICON_NAME="toast"
PKG_PATH="$DIST_DIR/Toast.pkg"

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION="$(read_plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(read_plist_value CFBundleVersion)"

echo "Building Toast for Mac App Store (release)..."
cd "$ROOT"
swift package reset
swift package resolve
swift build -c release

echo "Packaging $APP_NAME.app..."
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

# Mac App Store builds must not ship Sparkle update metadata.
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true

LAUNCHER_APP_DIR="$APP_DIR/Contents/Library/LoginItems/ToastLauncher.app"
mkdir -p "$LAUNCHER_APP_DIR/Contents/MacOS"
cp "$BUILD_DIR/$LAUNCHER_NAME" "$LAUNCHER_APP_DIR/Contents/MacOS/$LAUNCHER_NAME"
cp "$LAUNCHER_INFO_PLIST" "$LAUNCHER_APP_DIR/Contents/Info.plist"
chmod +x "$LAUNCHER_APP_DIR/Contents/MacOS/$LAUNCHER_NAME"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $LAUNCHER_BUNDLE_ID" "$LAUNCHER_APP_DIR/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $LAUNCHER_BUNDLE_ID" "$LAUNCHER_APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$LAUNCHER_APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$LAUNCHER_APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

echo "Compiling app icon..."
ICON_BUILD_DIR="$DIST_DIR/icon-build"
ICON_INFO_PLIST="$DIST_DIR/icon-info.plist"
rm -rf "$ICON_BUILD_DIR"
mkdir -p "$ICON_BUILD_DIR"
xcrun actool "$ICON_SOURCE" \
    --compile "$ICON_BUILD_DIR" \
    --app-icon "$ICON_NAME" \
    --output-partial-info-plist "$ICON_INFO_PLIST" \
    --include-all-app-icons \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --platform macosx
cp "$ICON_BUILD_DIR/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
cp "$ICON_BUILD_DIR/${ICON_NAME}.icns" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
rm -rf "$ICON_BUILD_DIR" "$ICON_INFO_PLIST"

if [[ -n "${PROVISIONING_PROFILE_PATH:-}" ]]; then
    echo "Embedding Mac App Store provisioning profile..."
    cp "$PROVISIONING_PROFILE_PATH" "$APP_DIR/Contents/embedded.provisionprofile"
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    chmod +x "$ROOT/scripts/codesign-app.sh"
    echo "Signing (Mac App Store)..."
    "$ROOT/scripts/codesign-app.sh" \
        "$APP_DIR" \
        "$SIGN_IDENTITY" \
        "$ENTITLEMENTS" \
        "$LAUNCHER_ENTITLEMENTS"
else
    echo "Skipping signing — set SIGN_IDENTITY to sign for App Store upload."
fi

if [[ "${CREATE_PKG:-}" == "1" ]]; then
    if [[ -z "${SIGN_IDENTITY:-}" ]]; then
        echo "Error: CREATE_PKG=1 requires SIGN_IDENTITY."
        exit 1
    fi
    if [[ -z "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
        echo "Error: CREATE_PKG=1 requires INSTALLER_SIGN_IDENTITY (Mac Installer Distribution)."
        exit 1
    fi
    echo "Creating signed .pkg..."
    rm -f "$PKG_PATH"
    pkgbuild \
        --component "$APP_DIR" \
        --install-location "/Applications" \
        --identifier "$BUNDLE_ID.pkg" \
        --version "$VERSION" \
        "$DIST_DIR/Toast-unsigned.pkg"
    productsign \
        --sign "$INSTALLER_SIGN_IDENTITY" \
        "$DIST_DIR/Toast-unsigned.pkg" \
        "$PKG_PATH"
    rm -f "$DIST_DIR/Toast-unsigned.pkg"
    echo "Package: $PKG_PATH"
fi

echo "Built Mac App Store app: $APP_DIR"
echo ""
echo "Restoring direct-download Swift package pins..."
unset APPSTORE
swift package resolve >/dev/null
echo ""
echo "Next steps:"
echo "  1. Upload with Transporter or Xcode Organizer"
echo "  2. See Toast/MAC_APP_STORE.md for App Store Connect setup"
