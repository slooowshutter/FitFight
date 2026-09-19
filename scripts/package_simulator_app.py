#!/usr/bin/env python3
"""Ad-hoc sign the simulator app with its capabilities before exporting it."""

from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
archive = Path(sys.argv[2]).resolve()
info = plistlib.loads((app / "Info.plist").read_bytes())
if "iPhoneSimulator" not in info["CFBundleSupportedPlatforms"]:
    raise SystemExit("This packager accepts simulator apps only, never device archives.")

bundle_id = info["CFBundleIdentifier"]
application_id = "C92DPD8ME2." + bundle_id
entitlements = plistlib.loads((root / "FitFight/FitFight.entitlements").read_bytes())
# CODE_SIGNING_ALLOWED=NO drops these; Google and Supabase cannot use Keychain without them.
entitlements["application-identifier"] = application_id
entitlements["com.apple.developer.team-identifier"] = "C92DPD8ME2"
entitlements["keychain-access-groups"] = [application_id]

with tempfile.TemporaryDirectory(prefix="fitfight-simulator-signing-") as directory:
    signing = Path(directory) / "entitlements.plist"
    signing.write_bytes(plistlib.dumps(entitlements))
    subprocess.run([
        "codesign", "--force", "--sign", "-", "--identifier", bundle_id,
        "--entitlements", str(signing), "--timestamp=none", str(app),
    ], check=True)

subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
print(f"Packaged {bundle_id} with simulator Keychain and app capabilities: {archive}")
