#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Vercel Status"
EXECUTABLE_NAME="VercelStatus"
BUNDLE_ID="com.vercelstatus.app"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Resources/VercelStatus.entitlements"
INFO_PLIST="$ROOT/Resources/Info.plist"

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION="$(read_plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(read_plist_value CFBundleVersion)"
ZIP_NAME="Vercel-Status-${VERSION}.zip"
ZIP_PATH="$ROOT/dist/$ZIP_NAME"
DMG_NAME="Vercel-Status-${VERSION}.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
DMG_STAGING="$ROOT/dist/dmg-staging"

echo "Building VercelStatus (release)..."
cd "$ROOT"
swift package resolve
swift build -c release

echo "Packaging $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

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

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" --options runtime "$APP_DIR"

echo "Creating $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Creating $DMG_NAME..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Vercel Status" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "Built: $APP_DIR"
echo "Install: $DMG_PATH"
echo "Update archive: $ZIP_PATH"
echo ""
echo "Run with:"
echo "  open \"$APP_DIR\""
