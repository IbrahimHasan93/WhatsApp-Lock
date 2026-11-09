#!/bin/bash
# Packages the built .app into a distributable .dmg with an /Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="WhatsApp Lock"
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "App bundle not found at '$APP_BUNDLE'. Run Scripts/build_app.sh first." >&2
  exit 1
fi

rm -f "$DMG_PATH"
STAGING="dist/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "==> Done: $DMG_PATH"
