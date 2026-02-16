#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# ============================================================================
# Configuration - UPDATE THESE
# ============================================================================
# Find your Team ID: https://developer.apple.com/account -> Membership -> Team ID
# Or run: security find-identity -v -p codesigning | grep "Developer ID"
TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"  # Your Apple ID email
APP_PASSWORD="${APP_PASSWORD:-}"  # App-specific password (not your Apple ID password)

# ============================================================================
# Validation
# ============================================================================
if [ -z "$TEAM_ID" ]; then
    echo "ERROR: TEAM_ID not set"
    echo ""
    echo "Find your Team ID at: https://developer.apple.com/account"
    echo "Or run: security find-identity -v -p codesigning"
    echo ""
    echo "Usage:"
    echo "  TEAM_ID=XXXXXXXXXX APPLE_ID=you@email.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx ./scripts/build-signed-dmg.sh"
    echo ""
    echo "To create an app-specific password:"
    echo "  https://appleid.apple.com -> Sign-In and Security -> App-Specific Passwords"
    exit 1
fi

if [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ]; then
    echo "WARNING: APPLE_ID or APP_PASSWORD not set - will skip notarization"
    echo "The app will be signed but users may still see Gatekeeper warnings."
    SKIP_NOTARIZATION=true
fi

SIGNING_IDENTITY="$(security find-identity -v -p codesigning | grep "$TEAM_ID" | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')"

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "ERROR: Could not find Developer ID Application certificate for team $TEAM_ID"
    echo ""
    echo "Available signing identities:"
    security find-identity -v -p codesigning
    echo ""
    echo "If you don't have a Developer ID certificate:"
    echo "  1. Go to https://developer.apple.com/account/resources/certificates"
    echo "  2. Create a 'Developer ID Application' certificate"
    echo "  3. Download and install it in Keychain"
    exit 1
fi

echo "============================================"
echo "Building Signed DMG"
echo "============================================"
echo "Team ID: $TEAM_ID"
echo "Signing Identity: $SIGNING_IDENTITY"
echo ""

# ============================================================================
# Build
# ============================================================================
echo "Step 1/6: Building Release..."
xcodebuild -scheme VoidReader -configuration Release -derivedDataPath build/derived clean build -quiet

APP_PATH="build/derived/Build/Products/Release/VoidReader.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# ============================================================================
# Sign the app
# ============================================================================
echo "Step 2/6: Signing app..."

# Sign all nested components first (frameworks, helpers, plugins, etc.)
# Order matters: sign deepest items first, then containers

# Sign any dylibs
find "$APP_PATH" -name "*.dylib" | while read -r item; do
    echo "  Signing dylib: $(basename "$item")"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$item"
done

# Sign frameworks (sign the versioned binary inside, then the framework bundle)
find "$APP_PATH" -name "*.framework" -type d | while read -r framework; do
    echo "  Signing framework: $(basename "$framework")"
    # Find and sign the actual binary inside
    framework_name=$(basename "$framework" .framework)
    framework_binary="$framework/Versions/Current/$framework_name"
    if [ -f "$framework_binary" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$framework_binary"
    fi
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$framework"
done

# Sign app extensions (Quick Look, etc.) - these need special handling
find "$APP_PATH" -name "*.appex" -type d | while read -r appex; do
    echo "  Signing extension: $(basename "$appex")"
    # Sign the binary inside the extension
    appex_name=$(basename "$appex" .appex)
    appex_binary="$appex/Contents/MacOS/$appex_name"
    if [ -f "$appex_binary" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$appex_binary"
    fi
    # Sign the extension bundle
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$appex"
done

# Sign the main app last
echo "  Signing main app..."
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"

# Verify signature
echo "Step 3/6: Verifying signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "  ✓ Signature valid"

# ============================================================================
# Create DMG
# ============================================================================
echo "Step 4/6: Creating DMG..."

DMG_DIR="build/dmg-contents"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

DMG_PATH="build/VoidReader.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "VoidReader" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_DIR"

# Sign the DMG
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

# ============================================================================
# Notarize (if credentials provided)
# ============================================================================
if [ "$SKIP_NOTARIZATION" != "true" ]; then
    echo "Step 5/6: Notarizing with Apple (this may take a few minutes)..."

    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo "Step 6/6: Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    echo ""
    echo "============================================"
    echo "✓ Signed & Notarized DMG: build/VoidReader.dmg"
    echo "============================================"
else
    echo "Step 5/6: Skipping notarization (no credentials)"
    echo "Step 6/6: Skipping stapling"
    echo ""
    echo "============================================"
    echo "✓ Signed DMG: build/VoidReader.dmg"
    echo "  (Not notarized - users may see Gatekeeper warning)"
    echo "============================================"
fi

echo ""
echo "File size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""

# Verify everything
echo "Verification:"
codesign -dv --verbose=2 "$DMG_PATH" 2>&1 | grep -E "^(Authority|TeamIdentifier)" | head -5
echo ""
