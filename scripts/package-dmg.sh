#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MobiVerse"
VERSION="${VERSION:-1.0.0}"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
DMG_PATH="$ROOT_DIR/.build/$APP_NAME-$VERSION.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

"$ROOT_DIR/scripts/package-app.sh"

rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

/usr/bin/ditto "$APP_DIR" "$DMG_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Packaged DMG: $DMG_PATH"
