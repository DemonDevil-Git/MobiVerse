#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?Usage: smoke-test-dmg.sh /path/to/MobiVerse.dmg}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOUNT_DIR="$(mktemp -d /tmp/mobiverse-dmg-smoke.XXXXXX)"
INSTALL_DIR="$(mktemp -d /tmp/mobiverse-install-smoke.XXXXXX)"
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
  case "$INSTALL_DIR" in
    /tmp/mobiverse-install-smoke.*) rm -rf "$INSTALL_DIR" ;;
  esac
}
trap cleanup EXIT INT TERM

hdiutil verify "$DMG_PATH" >/dev/null
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
IS_MOUNTED=1

APP_PATH="$MOUNT_DIR/MobiVerse.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "DMG smoke test cannot find MobiVerse.app in: $DMG_PATH" >&2
  exit 1
fi

/usr/bin/ditto "$APP_PATH" "$INSTALL_DIR/MobiVerse.app"
INSTALLED_APP_PATH="$INSTALL_DIR/MobiVerse.app"

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP_PATH"
fi

detach_image
rmdir "$MOUNT_DIR"
bash "$SCRIPT_DIR/smoke-test-app.sh" "$INSTALLED_APP_PATH"
echo "DMG integrity, install-copy signature, and fresh-user launch smoke test passed: $DMG_PATH"
