#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Pin the reviewed runtime; an explicit UDID can select another installed iPhone.
simulator_id="${1:-}"
if [[ -z "$simulator_id" ]]; then
    simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
matches = [device for runtime, rows in devices.items() if runtime.endswith("iOS-26-5")
           for device in rows if device["name"] == "iPhone 17"]
if not matches:
    sys.exit("iPhone 17 on iOS 26.5 is unavailable. Pass an installed iPhone Simulator UDID.")
print(matches[0]["udid"])
')"
fi

mkdir -p .context
xcodebuild -project FitFight.xcodeproj -scheme FitFight -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath .context/DerivedData \
    -clonedSourcePackagesDirPath .context/SourcePackages \
    CODE_SIGNING_ALLOWED=NO build > .context/companion-build.log 2>&1

xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" .context/DerivedData/Build/Products/Debug-iphonesimulator/FitFight.app
SIMCTL_CHILD_FF_COMPANION_PREVIEW=1 xcrun simctl launch --terminate-running-process \
    "$simulator_id" com.fitfight.mvp --companion-preview
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
printf 'Companion preview is running on %s. Open You → Companion preview for display states.\n' "$simulator_id"
