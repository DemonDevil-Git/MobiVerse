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

localized_strings="$resource_path/zh-Hans.lproj/Localizable.strings"
if [[ ! -f "$localized_strings" ]]; then
  echo "App smoke test cannot find packaged localization: $localized_strings" >&2
  exit 1
fi

APP_PID=""
fresh_user_dir="$(mktemp -d /tmp/mobiverse-smoke-user.XXXXXX)"
stdout_log="$fresh_user_dir/stdout.log"
stderr_log="$fresh_user_dir/stderr.log"
cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    exit_deadline=$((SECONDS + 4))
    while kill -0 "$APP_PID" 2>/dev/null && (( SECONDS < exit_deadline )); do
      sleep 0.25
    done
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill -9 "$APP_PID" 2>/dev/null || true
    fi
  fi
  case "$fresh_user_dir" in
    /tmp/mobiverse-smoke-user.*) rm -rf "$fresh_user_dir" ;;
  esac
}
trap cleanup EXIT INT TERM

open -n -F \
  --env "CFFIXED_USER_HOME=$fresh_user_dir" \
  --stdout "$stdout_log" \
  --stderr "$stderr_log" \
  "$APP_PATH" >/dev/null 2>&1

timeout_seconds="${APP_SMOKE_TIMEOUT_SECONDS:-12}"
stability_seconds="${APP_SMOKE_STABILITY_SECONDS:-5}"
deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  app_pid="$(ps -axo pid=,command= | awk -v executable="$EXECUTABLE_PATH" 'index($0, executable) && $0 !~ /awk|smoke-test-app\.sh|ps -axo/ { print $1; exit }')"
  if [[ -n "$app_pid" ]]; then
    APP_PID="$app_pid"
    stability_deadline=$((SECONDS + stability_seconds))
    while (( SECONDS < stability_deadline )); do
      if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "App launch smoke test failed: $APP_PATH exited during the ${stability_seconds}s stability window." >&2
        tail -n 80 "$stderr_log" >&2 2>/dev/null || true
        exit 1
      fi
      sleep 0.25
    done
    echo "App launch smoke test passed after ${stability_seconds}s: $APP_PATH"
    exit 0
  fi
  sleep 0.25
done

echo "App launch smoke test failed: $APP_PATH did not launch within ${timeout_seconds}s." >&2
tail -n 80 "$stderr_log" >&2 2>/dev/null || true
exit 1
