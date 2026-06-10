#!/usr/bin/env bash
# Run the Which Came First insufficient-events Maestro flow on an iOS simulator
# (port of Android commit e17bbd4e49). The On This Day REST endpoint is served
# from the local fixture server via the -WMFWikimediaRestAPIBaseURLOverride
# seam, using the 9-event fixture (4 real pairs + 1 leftover event) that forces
# the synthesized year+10 blank-event fallback on question 5.
#
# Usage: run-wikigames-insufficient.sh [simulator-udid]
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

maestro --device "$UDID" test .maestro/wikigames-insufficient-events.yaml

echo "Which Came First insufficient-events flow passed."
