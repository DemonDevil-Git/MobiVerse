#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?Usage: smoke-test-dmg.sh /path/to/MobiVerse.dmg}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOUNT_DIR="$(mktemp -d /tmp/mobiverse-dmg-smoke.XXXXXX)"
IS_MOUNTED=0

detach_image() {
  if hdiutil detach "$MOUNT_DIR" -quiet; then
    IS_MOUNTED=0
    return 0
  fi

  sleep 1
  hdiutil detach "$MOUNT_DIR" -force -quiet
  IS_MOUNTED=0
}

cleanup() {
  if [[ "$IS_MOUNTED" == "1" ]]; then
    detach_image 2>/dev/null || true
  fi
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
IS_MOUNTED=1

APP_PATH="$MOUNT_DIR/MobiVerse.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "DMG smoke test cannot find MobiVerse.app in: $DMG_PATH" >&2
  exit 1
fi

bash "$SCRIPT_DIR/smoke-test-app.sh" "$APP_PATH"

detach_image
rmdir "$MOUNT_DIR"
echo "DMG mount and fresh-user launch smoke test passed: $DMG_PATH"
