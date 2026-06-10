#!/usr/bin/env bash
# Run the Which Came First complete-on-last-answer Maestro flow on an iOS
# simulator (parity check for Android commit fe1486bbed). Answering the last
# question must persist the session as completed immediately, so a kill/relaunch
# at the final reveal shows the completed feed card and results screen. The On
# This Day REST endpoint is served from the local fixture server via the
# -WMFWikimediaRestAPIBaseURLOverride seam, using the 9-event fixture for a
# deterministic 5-question game.
#
# Usage: run-wikigames-complete-on-last.sh [simulator-udid]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=${1:-4FBD5440-8F42-4F6A-848E-00EB0BA507E6}   # iPhone 16 Pro
PORT=8081
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Wikipedia.app

if [ "${SKIP_BUILD:-}" != "1" ]; then
  xcodebuild -project Wikipedia.xcodeproj -scheme Wikipedia -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedData build
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

ONTHISDAY_FIXTURE=onthisday_events_insufficient.json \
  python3 .maestro/fixtures/server.py "$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

maestro --device "$UDID" test .maestro/wikigames-complete-on-last-answer.yaml

echo "Which Came First complete-on-last-answer flow passed."
