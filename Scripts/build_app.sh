#!/bin/bash
# Builds a release binary and assembles it into a proper WhatsApp Lock.app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="WhatsApp Lock"
EXEC_NAME="WhatsAppLock"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> Building release binary..."
swift build -c release

echo "==> Assembling app bundle..."
rm -rf "dist"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXEC_NAME" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc code signing (local use only, not notarized)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
