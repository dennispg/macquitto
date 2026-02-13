#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$BUILD_DIR/Macquitto.app"
DMG_PATH="$BUILD_DIR/Macquitto-${VERSION}.dmg"

# Build the .app first
"$SCRIPT_DIR/build-app.sh"

# Remove old DMG if it exists
rm -f "$DMG_PATH"

echo "Creating DMG..."
create-dmg \
    --volname "Macquitto" \
    --volicon "$APP_DIR/Contents/Resources/AppIcon.icns" \
    --background "$PROJECT_DIR/Icons/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 600 420 \
    --icon-size 128 \
    --icon "Macquitto.app" 150 195 \
    --app-drop-link 450 195 \
    --hide-extension "Macquitto.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_DIR"

echo "Done! DMG created at: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"
