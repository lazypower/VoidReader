#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Building Release..."
xcodebuild -scheme VoidReader -configuration Release -derivedDataPath build/derived clean build -quiet

echo "Creating DMG..."
APP_PATH="build/derived/Build/Products/Release/VoidReader.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Create a temporary directory for DMG contents
DMG_DIR="build/dmg-contents"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app
cp -R "$APP_PATH" "$DMG_DIR/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
DMG_PATH="build/VoidReader.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "VoidReader" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

# Cleanup
rm -rf "$DMG_DIR"

echo ""
echo "============================================"
echo "✓ DMG created: build/VoidReader.dmg"
echo "============================================"
echo ""
echo "File size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "This is UNSIGNED. Recipients will need to:"
echo "  Right-click VoidReader.app → Open (first launch only)"
echo ""
