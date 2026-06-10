#!/usr/bin/env bash
# Run the system-dark-theme Maestro flow on an iOS simulator (Android commit
# 8b7b08008f parity): with the theme preference at its default ("Match system
# theme" / themeName=standard), a dark system appearance must resolve to the
# DARK theme, not BLACK.
#
# Two passes: simulator appearance light (baseline), then appearance dark.
# theme(compatibleWith:) re-resolves on the trait change / next launch.
#
# Verdict is quantitative, from the dark main-screen and Appearance-screen
# screenshots: the Dark theme paper color #27292D must vastly outnumber pure
# black #000000 pixels. A pre-fix build resolves to the Black theme (paper
# #000000) and FAILS. (The Settings screen is captured for visual comparison
# only: its cells use midBackground, which is the same gray675 for the dark
# AND black themes, so it cannot discriminate.)
#
# Usage: run-system-dark-theme.sh [simulator-udid]
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
trap 'xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true' EXIT

xcrun simctl ui "$UDID" appearance light
maestro --device "$UDID" test --env STATE=light .maestro/system-dark-theme.yaml

xcrun simctl ui "$UDID" appearance dark
maestro --device "$UDID" test --env STATE=dark .maestro/system-dark-theme.yaml

xcrun simctl ui "$UDID" appearance light

# Quantitative theme check: pixel counts of the two candidate paper colors.
python3 - <<'EOF'
import subprocess, sys

def color_counts(path, colors):
    out = subprocess.run(
        ["magick", path, "-depth", "8", "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True, check=True).stdout
    counts = {c: 0 for c in colors}
    total = 0
    for line in out.splitlines():
        line = line.strip()
        if not line or ":" not in line or "#" not in line:
            continue
        n = int(line.split(":", 1)[0])
        hexcol = line.split("#", 1)[1].split()[0][:6].upper()
        total += n
        if hexcol in counts:
            counts[hexcol] += n
    return counts, total

DARK, BLACK, WHITE = "27292D", "000000", "FFFFFF"

ok = True

c, total = color_counts(".maestro/screenshots/ios-system-dark-theme-settings-light.png", [WHITE, DARK, BLACK])
good = c[WHITE] > c[DARK] + c[BLACK]
ok = ok and good
print(f"{'PASS' if good else 'FAIL'}: light baseline settings: white={c[WHITE]}, dark-paper={c[DARK]}, black={c[BLACK]} (of {total})")

for name, label in [("main-dark", "system-dark main screen"), ("chooser-dark", "system-dark appearance screen")]:
    c, total = color_counts(f".maestro/screenshots/ios-system-dark-theme-{name}.png", [DARK, BLACK])
    # paperBackground is the discriminator: #27292D (dark) vs #000000 (black).
    # On these screens it dominates (millions of pixels post-fix; pre-fix
    # flips them to pure black).
    good = c[DARK] > c[BLACK] and c[DARK] > 20000
    ok = ok and good
    print(f"{'PASS' if good else 'FAIL'}: {label}: dark-paper #27292D={c[DARK]}, black #000000={c[BLACK]} (of {total})")

if not ok:
    print("FAIL: pre-fix behavior resolves the system Dark default to the Black theme")
sys.exit(0 if ok else 1)
EOF
