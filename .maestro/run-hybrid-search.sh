#!/usr/bin/env bash
# Run the hybrid-search Maestro flows on an iOS simulator against the local
# semantic-API fixture server. Mirrors the Android flows of the same names
# (apps-android-wikipedia/.maestro). Lexical search runs live; only the
# semantic endpoint is mocked (via the -WMFSemanticSearchBaseURL seam).
#
# As of the 517351d4cd sync (hybrid search instrumentation) each scenario also
# asserts that the expected TestKitchen events were submitted. Debug builds
# append every submitted event as a single JSON line to tmp/tkev.log in the
# app container (see TestKitchenAdapter.sendEvents); clearState at flow launch
# resets the file, so it holds exactly the scenario's events.
#
# Usage: run-hybrid-search.sh [simulator-udid]
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

expect_events() {
  # expect_events <scenario-name> <pattern>...
  # Each pattern must appear in some line of the app's tkev.log.
  local scenario=$1; shift
  local container log=""
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
  local deadline=$((SECONDS + 15))
  local missing=("$@")
  while [ ${#missing[@]} -gt 0 ] && [ $SECONDS -lt $deadline ]; do
    log=$(cat "$container/tmp/tkev.log" 2>/dev/null || true)
    local still=()
    for pattern in "${missing[@]}"; do
      if ! grep -qF "$pattern" <<<"$log"; then
        still+=("$pattern")
      fi
    done
    missing=("${still[@]+"${still[@]}"}")
    [ ${#missing[@]} -gt 0 ] && sleep 2
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "FAIL [$scenario]: missing expected TestKitchen events:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
  echo "OK [$scenario]: all expected TestKitchen events observed."
}

maestro --device "$UDID" test .maestro/hybrid-search-onboarding.yaml
expect_events onboarding \
  '"funnel_name":"hybrid_search_onboarding"' \
  '"element_id":"onboarding_query"' \
  '"enrolled":"apps_hybridsearch"' \
  '"assigned":"lexicalsemantic"' \
  '"action":"show_hybrid_result"' \
  '"action":"search_impression"'

maestro --device "$UDID" test .maestro/hybrid-search-results.yaml
expect_events results \
  '"action":"search_impression"' \
  '"action":"search_init"' \
  '"action":"show_hybrid_result"' \
  '"element_id":"semantic_search_card"' \
  '"element_id":"thumb_up"' \
  '"assigned":"semanticlexical"'

maestro --device "$UDID" test .maestro/hybrid-search-close-button.yaml
expect_events close-button \
  '"element_id":"search_close"' \
  '"element_id":"search_back"'

maestro --device "$UDID" test .maestro/hybrid-search-control.yaml
expect_events control \
  '"action":"search_impression"' \
  '"action":"search_init"' \
  '"action":"show_search_result"' \
  '"assigned":"control"'

echo "All hybrid-search flows passed."
