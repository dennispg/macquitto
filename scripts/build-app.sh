#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Macquitto"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"

echo "Building release binary..."
swift build -c release --package-path "$PROJECT_DIR"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy resource bundle
cp -R "$BUILD_DIR/Macquitto_Macquitto.bundle" "$APP_DIR/Contents/Resources/"

# Copy app icon
if [ -f "$BUILD_DIR/Macquitto_Macquitto.bundle/AppIcon.icns" ]; then
    cp "$BUILD_DIR/Macquitto_Macquitto.bundle/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Macquitto</string>
    <key>CFBundleIdentifier</key>
    <string>com.macquitto.app</string>
    <key>CFBundleName</key>
    <string>Macquitto</string>
    <key>CFBundleDisplayName</key>
    <string>Macquitto</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Done! App bundle created at: $APP_DIR"
echo "Size: $(du -sh "$APP_DIR" | cut -f1)"
