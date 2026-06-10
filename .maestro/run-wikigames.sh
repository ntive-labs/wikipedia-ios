#!/usr/bin/env bash
# Run the WikiGames-card dismiss/undo Maestro flow on an iOS simulator.
# Mirrors apps-android-wikipedia/.maestro/run-wikigames.sh. The On This Day
# availability data behind the games card is served from the local fixture
# server via the -WMFWikimediaRestAPIBaseURLOverride seam; the rest of the
# feed loads live.
#
# Usage: run-wikigames.sh [simulator-udid]
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

python3 .maestro/fixtures/server.py "$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

maestro --device "$UDID" test .maestro/wikigames-card-dismiss.yaml

echo "WikiGames card flow passed."
