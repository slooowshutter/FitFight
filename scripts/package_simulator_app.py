#!/usr/bin/env python3
"""Export an Xcode-signed simulator app without losing its embedded capabilities."""

from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
archive = Path(sys.argv[2]).resolve()
info = plistlib.loads((app / "Info.plist").read_bytes())
if "iPhoneSimulator" not in info["CFBundleSupportedPlatforms"]:
    raise SystemExit("This packager accepts simulator apps only, never device archives.")

# Simulator reads iOS capabilities from Mach-O sections, not the host's code signature.
sections = subprocess.check_output([
    "xcrun", "otool", "-l", str(app / info["CFBundleExecutable"]),
], text=True)
if "sectname __entitlements" not in sections or "sectname __ents_der" not in sections:
    raise SystemExit("Missing simulator entitlements. Build with Xcode ad-hoc signing enabled.")

subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
print(f"Packaged {info['CFBundleIdentifier']} with embedded simulator capabilities: {archive}")
