#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MobiVerse"
EXECUTABLE_NAME="Mobi2EpubTransfer"
APP_VERSION="${APP_VERSION:-2.4.1}"
APP_BUILD="${APP_BUILD:-14}"
CALIBRE_APP="${CALIBRE_APP:-/Applications/calibre.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.mobiverse.app}"
CODESIGN_ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-}"
EPUBCHECK_JAR="${EPUBCHECK_JAR:-}"
EPUBCHECK_JAVA_HOME="${EPUBCHECK_JAVA_HOME:-}"

APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
THIRD_PARTY_DIR="$RESOURCES_DIR/ThirdParty"
BINARY_PATH="$ROOT_DIR/.build/release/$EXECUTABLE_NAME"
RESOURCE_BUNDLE_NAME="${EXECUTABLE_NAME}_Mobi2EpubTransfer.bundle"
RESOURCE_BUNDLE_PATH="$ROOT_DIR/.build/release/$RESOURCE_BUNDLE_NAME"
RESOURCE_BUNDLE_DESTINATION="$RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
APP_ICON="$ROOT_DIR/Assets/AppIcon/AppIcon.icns"

if [[ ! -d "$CALIBRE_APP" ]]; then
  echo "Calibre app not found at: $CALIBRE_APP" >&2
  echo "Install Calibre or run with CALIBRE_APP=/path/to/calibre.app" >&2
  exit 1
fi

if [[ ! -x "$CALIBRE_APP/Contents/MacOS/ebook-convert" || ! -x "$CALIBRE_APP/Contents/MacOS/ebook-meta" ]]; then
  echo "Calibre CLI tools were not found inside: $CALIBRE_APP" >&2
  exit 1
fi

if [[ -z "$EPUBCHECK_JAR" ]]; then
  for candidate in \
    /opt/homebrew/opt/epubcheck/libexec/epubcheck.jar \
    /usr/local/opt/epubcheck/libexec/epubcheck.jar \
    /opt/homebrew/share/java/epubcheck.jar \
    /usr/local/share/java/epubcheck.jar; do
    if [[ -f "$candidate" ]]; then
      EPUBCHECK_JAR="$candidate"
      break
    fi
  done
fi

if [[ -z "$EPUBCHECK_JAR" || ! -f "$EPUBCHECK_JAR" ]]; then
  echo "EPUBCheck JAR was not found." >&2
  echo "Install EPUBCheck or run with EPUBCHECK_JAR=/path/to/epubcheck.jar" >&2
  echo "MobiVerse refuses to create validation or release packages without EPUBCheck." >&2
  exit 1
fi

if [[ -z "$EPUBCHECK_JAVA_HOME" ]]; then
  for candidate in \
    /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home \
    /usr/local/opt/openjdk/libexec/openjdk.jdk/Contents/Home; do
    if [[ -x "$candidate/bin/java" ]]; then
      EPUBCHECK_JAVA_HOME="$candidate"
      break
    fi
  done
fi

if [[ -z "$EPUBCHECK_JAVA_HOME" || ! -x "$EPUBCHECK_JAVA_HOME/bin/java" ]]; then
  echo "A Java runtime for bundled EPUBCheck was not found." >&2
  echo "Install Homebrew OpenJDK or set EPUBCHECK_JAVA_HOME=/path/to/java/home" >&2
  echo "MobiVerse refuses to create packages with a non-runnable EPUBCheck bundle." >&2
  exit 1
fi

swift build -c release --product "$EXECUTABLE_NAME"

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "SwiftPM resource bundle not found at: $RESOURCE_BUNDLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$THIRD_PARTY_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Sources/Mobi2EpubTransfer/Resources/"*.png "$RESOURCES_DIR/"
/usr/bin/ditto "$RESOURCE_BUNDLE_PATH" "$RESOURCE_BUNDLE_DESTINATION"
if [[ -d "$ROOT_DIR/Sources/Mobi2EpubTransfer/Resources/zh-Hans.lproj" ]]; then
  /usr/bin/ditto "$ROOT_DIR/Sources/Mobi2EpubTransfer/Resources/zh-Hans.lproj" "$RESOURCES_DIR/zh-Hans.lproj"
fi
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi

/usr/bin/ditto "$CALIBRE_APP" "$THIRD_PARTY_DIR/calibre.app"

mkdir -p "$THIRD_PARTY_DIR/epubcheck"
EPUBCHECK_SOURCE_DIR="$(cd "$(dirname "$EPUBCHECK_JAR")" && pwd)"
if [[ -d "$EPUBCHECK_SOURCE_DIR/lib" ]]; then
  /usr/bin/ditto "$EPUBCHECK_SOURCE_DIR/lib" "$THIRD_PARTY_DIR/epubcheck/lib"
fi
cp "$EPUBCHECK_JAR" "$THIRD_PARTY_DIR/epubcheck/epubcheck.jar"
/usr/bin/ditto "$EPUBCHECK_JAVA_HOME" "$THIRD_PARTY_DIR/java"
cat > "$THIRD_PARTY_DIR/epubcheck/epubcheck" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../java/bin/java" -jar "$SCRIPT_DIR/epubcheck.jar" "$@"
WRAPPER
chmod +x "$THIRD_PARTY_DIR/epubcheck/epubcheck"

cp "$ROOT_DIR/ThirdPartyNotices.md" "$RESOURCES_DIR/ThirdPartyNotices.md"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>epub</string>
        <string>mobi</string>
        <string>azw</string>
        <string>azw3</string>
        <string>cbz</string>
        <string>cbr</string>
        <string>zip</string>
        <string>pdf</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>Ebook and comic files</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
    </dict>
  </array>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Code signing app with ad-hoc identity. This build is for local development only."
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
  else
    if [[ -n "$CODESIGN_ENTITLEMENTS" && ! -f "$CODESIGN_ENTITLEMENTS" ]]; then
      echo "CODESIGN_ENTITLEMENTS does not exist: $CODESIGN_ENTITLEMENTS" >&2
      exit 1
    fi

    sign_args=(--force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY")
    if [[ -n "$CODESIGN_ENTITLEMENTS" ]]; then
      sign_args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
    fi

    echo "Code signing app with Developer ID identity: $SIGN_IDENTITY"
    codesign "${sign_args[@]}" "$APP_DIR"
  fi

  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

for resource_name in hero-books-background reading-still-life; do
  if [[ ! -f "$RESOURCES_DIR/$resource_name.png" \
     || ! -f "$RESOURCE_BUNDLE_DESTINATION/$resource_name.png" ]]; then
    echo "Required app resource was not packaged: $resource_name.png" >&2
    exit 1
  fi
done

if [[ ! -x "$THIRD_PARTY_DIR/calibre.app/Contents/MacOS/ebook-convert" \
   || ! -x "$THIRD_PARTY_DIR/calibre.app/Contents/MacOS/ebook-meta" ]]; then
  echo "Packaged app is missing bundled Calibre CLI tools." >&2
  exit 1
fi

if [[ ! -f "$THIRD_PARTY_DIR/epubcheck/epubcheck.jar" \
   || ! -x "$THIRD_PARTY_DIR/epubcheck/epubcheck" \
   || ! -x "$THIRD_PARTY_DIR/java/bin/java" ]]; then
  echo "Packaged app is missing bundled EPUBCheck." >&2
  exit 1
fi

if [[ "${SKIP_APP_SMOKE_TEST:-0}" != "1" ]]; then
  bash "$ROOT_DIR/scripts/smoke-test-app.sh" "$APP_DIR"
fi

echo "Packaged app: $APP_DIR"
echo "App version: $APP_VERSION ($APP_BUILD)"
echo "SwiftPM resources: $RESOURCE_BUNDLE_DESTINATION"
if [[ -f "$APP_ICON" ]]; then
  echo "App icon: $APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "App icon: missing"
fi
echo "Bundled Calibre: $APP_DIR/Contents/Resources/ThirdParty/calibre.app"
echo "Bundled EPUBCheck: $APP_DIR/Contents/Resources/ThirdParty/epubcheck/epubcheck.jar"
echo "Bundled Java runtime: $APP_DIR/Contents/Resources/ThirdParty/java"
