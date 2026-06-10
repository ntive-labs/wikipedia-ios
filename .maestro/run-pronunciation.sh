#!/usr/bin/env bash
# Pronunciation User-Agent flow (Android 6c43d3fe3c parity): the AVPlayer-backed
# pronunciation audio request must carry the app User-Agent (WikipediaApp/...)
# instead of the platform default (AppleCoreMedia/...).
#
# The DEBUG -WMFAudioURLHostOverride launch argument redirects the audio fetch
# (already rewritten by the Router to the transcoded .mp3) to the local fixture
# server, which logs every request's User-Agent; after the flow taps the live
# Beer article's pronunciation control, this runner asserts the mp3 request UA.
#
# Usage: run-pronunciation.sh [simulator-udid]
# Env: SKIP_BUILD=1 to reuse the previously built app.
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=${1:-4FBD5440-8F42-4F6A-848E-00EB0BA507E6}   # iPhone 16 Pro
PORT=8081
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Wikipedia.app
SERVER_LOG=$(mktemp /tmp/ios-pron-ua-fixture-log.XXXXXX)

if [ "${SKIP_BUILD:-}" != "1" ]; then
  xcodebuild -project Wikipedia.xcodeproj -scheme Wikipedia -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedData build
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

python3 .maestro/fixtures/server.py "$PORT" 2>"$SERVER_LOG" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

maestro --device "$UDID" test .maestro/pronunciation-user-agent.yaml

# Server-side assertion: the audio request must arrive with the app UA.
deadline=$((SECONDS + 20))
while [ $SECONDS -lt $deadline ]; do
  if grep "test-pron.mp3" "$SERVER_LOG" | grep -q "UA=WikipediaApp/"; then
    echo "OK: pronunciation audio request sent the app User-Agent:"
    grep "test-pron.mp3" "$SERVER_LOG"
    exit 0
  fi
  sleep 2
done

echo "FAIL: no audio request with UA=WikipediaApp/ observed." >&2
echo "--- full fixture log: ---" >&2
cat "$SERVER_LOG" >&2
exit 1
