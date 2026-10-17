#!/bin/bash
# Puts the real app and the HTML app mirror side by side, for every screen the app can be launched straight into.
#   scripts/app-mirror-check.sh            builds the app, then captures
#   scripts/app-mirror-check.sh --no-build reuses the last build in .context/DerivedData
# Writes .context/mirror-check/<theme>-<screen>.png: the Simulator on the left, docs/design/source/kit/app.html on
# the right, at 1x. Both use the Companion preview people and fights (FitFight/CompanionPreview.swift).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=.context/mirror-check
mkdir -p "$out"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$chrome" ]] || { echo "Google Chrome is needed to render the mirror." >&2; exit 1; }

# The same per-workspace Simulator as scripts/run-simulator.sh.
workspace="$(basename "$PWD")"
simulator_id="$(xcrun simctl list devices available | grep -F "FitFight $workspace (" | grep -oE '[0-9A-F-]{36}' || true)"
[[ -n "$simulator_id" ]] || simulator_id="$(xcrun simctl create "FitFight $workspace" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
xcrun simctl boot "$simulator_id" 2> /dev/null || true
xcrun simctl bootstatus "$simulator_id" -b > /dev/null
if [[ "${1:-}" != --no-build ]]; then
    xcodebuild -project FitFight.xcodeproj -scheme FitFight -configuration Debug \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath .context/DerivedData -clonedSourcePackagesDirPath .context/SourcePackages \
        CODE_SIGNING_ALLOWED=NO build > .context/mirror-check-build.log 2>&1 || { tail -30 .context/mirror-check-build.log; exit 1; }
fi
xcrun simctl install "$simulator_id" .context/DerivedData/Build/Products/Debug-iphonesimulator/FitFight.app
xcrun simctl status_bar "$simulator_id" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

page="$PWD/docs/design/source/kit/app.html"
capture() { # name, mirror route, mirror query, then the app's launch variables
    local name="$1" route="$2" query="$3"
    shift 3
    env SIMCTL_CHILD_FF_COMPANION_PREVIEW=1 "${@/#/SIMCTL_CHILD_}" \
        xcrun simctl launch "$simulator_id" com.fitfight.mvp -AppleLanguages "(en)" -AppleLocale en_US > /dev/null
    sleep 7
    xcrun simctl io "$simulator_id" screenshot "$out/$name-app.png" > /dev/null 2>&1
    xcrun simctl terminate "$simulator_id" com.fitfight.mvp 2> /dev/null || true
    local profile
    profile="$(mktemp -d)"
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$profile" --allow-file-access-from-files \
        --force-device-scale-factor=3 --window-size=402,874 --virtual-time-budget=4000 \
        --screenshot="$out/$name-mirror.png" "file://$page?shot=1&$query$route" > /dev/null 2>&1
    rm -rf "$profile"
    python3 - "$out/$name" << 'PY' || echo "Pillow is missing: compare $1-app.png and $1-mirror.png by eye."
import sys
from PIL import Image
base = sys.argv[1]
app, mirror = (Image.open(f"{base}-{side}.png").convert("RGB").resize((402, 874)) for side in ("app", "mirror"))
sheet = Image.new("RGB", (814, 874), (255, 0, 255))
sheet.paste(app, (0, 0))
sheet.paste(mirror, (412, 0))
sheet.save(f"{base}.png")
PY
    echo "$out/$name.png"
}

for theme in night day; do
    capture "$theme-fights" "#fights" "theme=$theme" FF_SHOOT=1 FF_SHOT=fights FF_COMPANION_THEME=$theme
    capture "$theme-fight" "#fights/fight?id=duel" "theme=$theme" FF_SHOOT=1 FF_SHOT=fight FF_COMPANION_THEME=$theme
    capture "$theme-invitation" "#fights/fight?id=invite" "theme=$theme" FF_SHOOT=1 FF_SHOT=invitation FF_COMPANION_THEME=$theme
    capture "$theme-new" "#newFight" "theme=$theme" FF_SHOOT=1 FF_SHOT=new FF_COMPANION_THEME=$theme
    capture "$theme-feed" "#feed" "theme=$theme" FF_SHOOT=1 FF_SHOT=feed FF_COMPANION_THEME=$theme
    capture "$theme-you" "#you" "theme=$theme" FF_SHOOT=1 FF_SHOT=you FF_COMPANION_THEME=$theme
done
for state in tied solo deferred pending finished empty loading; do
    capture "night-fights-$state" "#fights" "scenario=$state" FF_SHOOT=1 FF_SHOT=fights FF_COMPANION_STATE=$state
done
capture night-companion-picker "#you/~companionPicker?tab=specials&selection=limited-black-panther" "" FF_COMPANION_PICKER=1
for state in describe checking review portraits choosing poses done; do
    capture "night-character-$state" "#fights/~paidCharacter?state=$state" "" FF_CHARACTER=$state
done
