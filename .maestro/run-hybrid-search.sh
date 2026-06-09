#!/usr/bin/env bash
# Run the hybrid-search Maestro flows on an iOS simulator against the local
# semantic-API fixture server. Mirrors the Android flows of the same names
# (apps-android-wikipedia/.maestro). Lexical search runs live; only the
# semantic endpoint is mocked (via the -WMFSemanticSearchBaseURL seam).
#
# Usage: run-hybrid-search.sh [simulator-udid]
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

maestro --device "$UDID" test .maestro/hybrid-search-onboarding.yaml
maestro --device "$UDID" test .maestro/hybrid-search-results.yaml
maestro --device "$UDID" test .maestro/hybrid-search-control.yaml

echo "All hybrid-search flows passed."
