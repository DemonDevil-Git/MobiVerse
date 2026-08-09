#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: smoke-test-app.sh /path/to/MobiVerse.app}"
EXECUTABLE_NAME="Mobi2EpubTransfer"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "App smoke test cannot find executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

resource_path="$APP_PATH/Contents/Resources/Mobi2EpubTransfer_Mobi2EpubTransfer.bundle"
if [[ ! -d "$resource_path" ]]; then
  echo "App smoke test cannot find SwiftPM resource bundle: $resource_path" >&2
  exit 1
fi

APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

open -n "$APP_PATH" >/dev/null 2>&1

timeout_seconds="${APP_SMOKE_TIMEOUT_SECONDS:-12}"
deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  app_pid="$(ps -axo pid=,command= | awk -v executable="$EXECUTABLE_PATH" 'index($0, executable) && $0 !~ /awk|smoke-test-app\.sh|ps -axo/ { print $1; exit }')"
  if [[ -n "$app_pid" ]]; then
    APP_PID="$app_pid"
    echo "App launch smoke test passed: $APP_PATH"
    exit 0
  fi
  sleep 0.25
done

echo "App launch smoke test failed: $APP_PATH did not remain running for ${timeout_seconds}s." >&2
exit 1
