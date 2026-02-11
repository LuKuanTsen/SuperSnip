#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>  (e.g. 0.0.1)}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_NAME="Super Snip"
APP_BUNDLE="$PROJECT_ROOT/dist/${APP_NAME}.app"
ZIP_OUTPUT="$PROJECT_ROOT/dist/SuperSnip-v${VERSION}.zip"

echo "==> Building release binary..."
swift build -c release --package-path "$PROJECT_ROOT"

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/SuperSnip" "$APP_BUNDLE/Contents/MacOS/SuperSnip"

# Copy Info.plist and stamp version
cp "$PROJECT_ROOT/SuperSnip/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy entitlements (for reference; used during codesign)
ENTITLEMENTS="$PROJECT_ROOT/SuperSnip/SuperSnip.entitlements"

# Ad-hoc code sign
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

# Zip for distribution
echo "==> Packaging zip..."
rm -f "$ZIP_OUTPUT"
cd "$PROJECT_ROOT/dist"
zip -r -y "$(basename "$ZIP_OUTPUT")" "$(basename "$APP_BUNDLE")"

echo ""
echo "Done!"
echo "  App:  $APP_BUNDLE"
echo "  Zip:  $ZIP_OUTPUT"
echo "  Version: $VERSION"
