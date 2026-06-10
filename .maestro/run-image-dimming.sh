#!/usr/bin/env bash
# Run the dark-mode image-dimming Maestro flow on an iOS simulator, then verify
# the dimming coefficient quantitatively. Mirrors the Android flow of the same
# name (apps-android-wikipedia/.maestro/run-image-dimming.sh).
#
# iOS dims native images by setting imageView.alpha = Theme.dimmedImageOpacity
# on dark/black themes when "Dim images" is on. With the mobile-web-matched
# coefficient (0.8, Android commit 2e336358d3 parity) the App theme screen's
# example image keeps ~80% of its luminance when dimmed; the previous 0.65
# kept only ~65–70%. The flow captures the same settings screen with dimming
# off and on seconds apart, so the per-pixel luminance ratio over the example
# image region is a direct measurement of the coefficient.
#
# Usage: run-image-dimming.sh [simulator-udid]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=${1:-4FBD5440-8F42-4F6A-848E-00EB0BA507E6}   # iPhone 16 Pro
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Wikipedia.app

if [ "${SKIP_BUILD:-}" != "1" ]; then
  xcodebuild -project Wikipedia.xcodeproj -scheme Wikipedia -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedData build
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

maestro --device "$UDID" test .maestro/image-dimming.yaml

# Quantitative coefficient check over the dim-images example image: compare the
# dimmed vs undimmed App theme screenshots pixel-by-pixel and take the median
# luminance ratio across pixels that visibly changed and were bright enough for
# the ratio to be meaningful.
python3 - <<'EOF'
import subprocess, statistics, sys

def pixels(path):
    out = subprocess.run(["magick", path, "-depth", "8", "txt:-"],
                         capture_output=True, text=True, check=True).stdout
    px = {}
    for line in out.splitlines()[1:]:
        try:
            coord, rest = line.split(":", 1)
            rgb = rest.split("(", 1)[1].split(")", 1)[0].split(",")
            r, g, b = (int(v) for v in rgb[:3])
        except (IndexError, ValueError):
            continue
        px[coord.strip()] = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return px

on = pixels(".maestro/screenshots/ios-image-dimming-theme-on.png")
off = pixels(".maestro/screenshots/ios-image-dimming-theme-off.png")
ratios = [on[k] / off[k] for k in off
          if k in on and off[k] >= 120 and abs(on[k] - off[k]) > 10]
if len(ratios) < 1000:
    print(f"FAIL: too few changed bright pixels ({len(ratios)}) — did the dim toggle work?")
    sys.exit(1)
med = statistics.median(ratios)
print(f"dimmed/undimmed luminance ratio over example image: median={med:.3f} (n={len(ratios)})")
ok = 0.76 <= med <= 0.92
print("PASS: dimming coefficient ~0.8 (mobile web parity)" if ok else
      "FAIL: expected median ratio in [0.76, 0.92] (old 0.65 constant gives ~0.65-0.70)")
sys.exit(0 if ok else 1)
EOF
