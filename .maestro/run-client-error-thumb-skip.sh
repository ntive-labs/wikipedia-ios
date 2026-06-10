#!/usr/bin/env bash
# 320px-thumbnail client-error skip flow (Android 763158c976 parity): HTTP
# failures (404) from requests whose URL contains "/320px-" must NOT be
# reported to the mediawiki.client.error logging-intake stream (known Commons
# rate-limit noise from old saved articles), while other HTTP failures must
# still be reported.
#
# The Wikimedia REST feed API is pointed at the local fixture server serving
# onthisday_events_thumb404.json: every On This Day event page has a thumbnail
# URL that 404s (fixture "errortrigger" rule) — 5 contain /320px- (must be
# skipped) and 4 control URLs contain /330px- (must be logged). The flow plays
# the full Which Came First game so every event card fetches its thumbnail via
# WMFImageDataController -> WMFBasicService -> httpErrorLoggingUtility ->
# ClientErrorFunnel.logHttpResponse, where the skip lives.
#
# Debug builds append every EventPlatformClient-submitted event as a single
# JSON line to tmp/epev.log in the app container; clearState at flow launch
# resets the container, so the log holds exactly this flow's events.
#
# Usage: run-client-error-thumb-skip.sh [simulator-udid]
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

ONTHISDAY_FIXTURE=onthisday_events_thumb404.json \
  python3 .maestro/fixtures/server.py "$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

maestro --device "$UDID" test .maestro/client-error-thumb-skip.yaml

EPEV_LOG="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/tmp/epev.log"

# Positive control: the /330px- thumbnail 404s MUST be reported as client errors.
expect_event() {
  local pattern=$1
  local deadline=$((SECONDS + 20))
  while [ $SECONDS -lt $deadline ]; do
    if grep '\\/mediawiki\\/client\\/error\\/2.0.0' "$EPEV_LOG" 2>/dev/null | grep -qF "$pattern"; then
      echo "OK: found client-error event with $pattern"
      return 0
    fi
    sleep 2
  done
  echo "FAIL: missing expected client-error event fragment: $pattern" >&2
  echo "--- epev.log contents: ---" >&2
  cat "$EPEV_LOG" >&2 2>/dev/null || true
  exit 1
}

expect_event '330px-errortrigger-log'
expect_event '"status_code":404'

# The fix under test: NO client-error event may reference a /320px- URL.
if grep '\\/mediawiki\\/client\\/error\\/2.0.0' "$EPEV_LOG" | grep -qF '320px-errortrigger-skip'; then
  echo 'FAIL: a /320px- thumbnail HTTP failure was reported to mediawiki.client.error.' >&2
  echo "--- offending epev.log lines: ---" >&2
  grep '\\/mediawiki\\/client\\/error\\/2.0.0' "$EPEV_LOG" | grep '320px-errortrigger-skip' >&2 || true
  exit 1
fi
echo "OK: no client-error event for /320px- thumbnails."

echo "Client-error 320px-thumbnail skip flow passed."
