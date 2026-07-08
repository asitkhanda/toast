#!/usr/bin/env bash
# Create a styled Toast installer DMG with checkpoint guidance.
# Falls back to a plain srcfolder DMG if Finder layout AppleScript fails
# (common in headless CI without GUI access).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:?Usage: package-dmg.sh <Toast.app> <output.dmg>}"
DMG_PATH="${2:?Usage: package-dmg.sh <Toast.app> <output.dmg>}"
VOL_NAME="Toast"
DMG_WINDOW_WIDTH=660
DMG_WINDOW_HEIGHT=420
ICON_SIZE=128
# Finder icon positions (logical points inside the window).
TOAST_X=140
TOAST_Y=165
APPS_X=520
APPS_Y=165
GUIDE_X=330
GUIDE_Y=300

BG_1X="$ROOT/Resources/dmg-background.png"
BG_2X="$ROOT/Resources/dmg-background@2x.png"
GUIDE_SRC="$ROOT/Resources/How to Open Toast.txt"
GEN_BG="$ROOT/scripts/generate-dmg-background.swift"

STAGING="$ROOT/dist/dmg-staging"
RW_DMG="$ROOT/dist/.Toast-rw.dmg"
MOUNT_DIR=""
BG_TIFF=""

cleanup() {
    if [[ -n "${MOUNT_DIR}" && -d "${MOUNT_DIR}" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet -force 2>/dev/null || true
    fi
    rm -f "$RW_DMG"
    rm -rf "$STAGING"
    if [[ -n "${BG_TIFF}" && -f "${BG_TIFF}" ]]; then
        rm -f "$BG_TIFF"
    fi
}
trap cleanup EXIT

ensure_backgrounds() {
    if [[ ! -f "$BG_1X" || ! -f "$BG_2X" ]]; then
        echo "Generating DMG backgrounds..."
        swift "$GEN_BG" "$BG_1X" "$BG_2X"
    fi
}

create_plain_dmg() {
    echo "Creating plain DMG (styled layout unavailable)..."
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp "$GUIDE_SRC" "$STAGING/How to Open Toast.txt"
    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$VOL_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"
    echo "Created plain DMG: $DMG_PATH"
}

create_styled_dmg() {
    ensure_backgrounds

    BG_TIFF="$(mktemp -t toast-dmg-bg).tiff"
    tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$BG_TIFF"

    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp "$GUIDE_SRC" "$STAGING/How to Open Toast.txt"

    local size_kb
    size_kb="$(du -sk "$STAGING" | awk '{print $1}')"
    # Extra room for background + Finder metadata.
    local dmg_kb=$((size_kb + 8192))
    if (( dmg_kb < 51200 )); then
        dmg_kb=51200
    fi

    rm -f "$RW_DMG"
    hdiutil create \
        -srcfolder "$STAGING" \
        -volname "$VOL_NAME" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -format UDRW \
        -size "${dmg_kb}k" \
        "$RW_DMG"

    MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk 'END {print $NF}')"
    if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
        echo "Warning: could not mount RW DMG"
        return 1
    fi

    mkdir -p "$MOUNT_DIR/.background"
    cp "$BG_TIFF" "$MOUNT_DIR/.background/background.tiff"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a V "$MOUNT_DIR/.background" || true
    fi

    local win_right=$((200 + DMG_WINDOW_WIDTH))
    local win_bottom=$((120 + DMG_WINDOW_HEIGHT))

    # AppleScript configures Finder icon layout + background.
    # Often unavailable in headless CI without a WindowServer session.
    if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $win_right, $win_bottom}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "Toast.app" to {$TOAST_X, $TOAST_Y}
        set position of item "Applications" to {$APPS_X, $APPS_Y}
        set position of item "How to Open Toast.txt" to {$GUIDE_X, $GUIDE_Y}
        update without registering applications
        delay 2
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT
    then
        echo "Warning: Finder AppleScript layout failed"
        hdiutil detach "$MOUNT_DIR" -quiet -force 2>/dev/null || true
        MOUNT_DIR=""
        return 1
    fi

    sync
    hdiutil detach "$MOUNT_DIR" -quiet
    MOUNT_DIR=""

    rm -f "$DMG_PATH"
    hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
    echo "Created styled DMG: $DMG_PATH"
}

echo "Packaging installer DMG..."
if create_styled_dmg; then
    exit 0
fi

echo "Falling back to plain DMG packaging..."
create_plain_dmg
