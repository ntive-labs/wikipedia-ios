#!/usr/bin/env bash
# Client-error logging flow (Android 2d908c3384 parity): an HTTP failure (404)
# from an API request must be submitted to the Event Platform as a
# /mediawiki/client/error/2.0.0 event on the mediawiki.client.error stream.
#
# Debug builds append every EventPlatformClient-submitted event as a single
# JSON line to tmp/epev.log in the app container (submit-time seam in
# EventPlatformClient._submit, mirroring the TKEV seam); clearState at flow
# launch resets the container, so the log holds exactly this flow's events.
#
# Usage: run-client-error.sh [simulator-udid]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=${1:-4FBD5440-8F42-4F6A-848E-00EB0BA507E6}   # iPhone 16 Pro
PORT=8081
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Wikipedia.app
BUNDLE_ID=org.wikimedia.wikipedia

if [ "${SKIP_BUILD:-}" != "1" ]; then
  xcodebuild -project Wikipedia.xcodeproj -scheme Wikipedia -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedData build
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

python3 .maestro/fixtures/server.py "$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

maestro --device "$UDID" test .maestro/client-error-logging.yaml

# Assert the client-error event was submitted with the expected serialized shape.
EPEV_LOG="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/tmp/epev.log"

expect_event() {
  local pattern=$1
  local deadline=$((SECONDS + 20))
  while [ $SECONDS -lt $deadline ]; do
    if grep -qF "$pattern" "$EPEV_LOG" 2>/dev/null; then
      echo "OK: found $pattern"
      return 0
    fi
    sleep 2
  done
  echo "FAIL: missing expected client-error event fragment: $pattern" >&2
  echo "--- epev.log contents: ---" >&2
  cat "$EPEV_LOG" >&2 2>/dev/null || true
  exit 1
}

expect_event '"$schema":"\/mediawiki\/client\/error\/2.0.0"'
expect_event '"stream":"mediawiki.client.error"'
expect_event '"error_class":"ClientErrorFunnel"'
expect_event '"status_code":404'
expect_event '"method":"GET"'
expect_event 'errortrigger'

# The client-error event must NOT carry a top-level dt (intake sets meta.dt).
if grep '\\/mediawiki\\/client\\/error\\/2.0.0' "$EPEV_LOG" | grep -qF '"dt"'; then
  echo 'FAIL: client-error event unexpectedly contains a "dt" field.' >&2
  exit 1
fi
echo "OK: client-error event carries no dt field."

echo "Client-error logging flow passed."
