#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MobiVerse"
VERSION="${VERSION:-2.0.1}"
APP_VERSION="${APP_VERSION:-$VERSION}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_DMG_IDENTITY="${SIGN_DMG_IDENTITY:-$SIGN_IDENTITY}"
NOTARIZE="${NOTARIZE:-0}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
DMG_PATH="$ROOT_DIR/.build/$APP_NAME-$VERSION.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

APP_VERSION="$APP_VERSION" "$ROOT_DIR/scripts/package-app.sh"

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

if [[ "$SIGN_DMG_IDENTITY" != "-" && -n "$SIGN_DMG_IDENTITY" ]]; then
  echo "Code signing DMG with identity: $SIGN_DMG_IDENTITY"
  codesign --force --timestamp --sign "$SIGN_DMG_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
else
  echo "DMG signing skipped. This installer image will trigger Gatekeeper after download."
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" || -z "$SIGN_IDENTITY" ]]; then
    echo "NOTARIZE=1 requires SIGN_IDENTITY to be a Developer ID Application certificate." >&2
    exit 1
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required for notarization." >&2
    exit 1
  fi

  submit_args=(notarytool submit "$DMG_PATH" --wait)
  if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    submit_args+=(--keychain-profile "$NOTARYTOOL_PROFILE")
  elif [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_APP_PASSWORD" ]]; then
    submit_args+=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  else
    echo "NOTARIZE=1 requires NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD." >&2
    exit 1
  fi

  echo "Submitting DMG for Apple notarization..."
  xcrun "${submit_args[@]}"

  echo "Stapling notarization ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "Notarization skipped. Set NOTARIZE=1 for public distribution builds."
fi

echo "Packaged DMG: $DMG_PATH"
