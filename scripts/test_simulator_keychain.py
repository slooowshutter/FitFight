#!/usr/bin/env python3
"""Reproduce missing-entitlement storage failure, then verify the exported signing path.

Uses a disposable CI simulator and the built app's bundle/resources. The probe
replaces only its executable, keeping the production bundle ID and capabilities.
"""

from pathlib import Path
import json
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Run this test only on a disposable GitHub-hosted simulator.")

root = Path(__file__).resolve().parents[1]
source_app = Path(sys.argv[1]).resolve()
device = sys.argv[2]
info = plistlib.loads((source_app / "Info.plist").read_bytes())
bundle_id = info["CFBundleIdentifier"]
sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()

with tempfile.TemporaryDirectory(prefix="fitfight-keychain-probe-") as directory:
    app = Path(directory) / "FitFight.app"
    shutil.copytree(source_app, app)
    subprocess.run([
        "xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5",
        "-parse-as-library", "-sdk", sdk,
        "-target", f"{platform.machine()}-apple-ios17.0-simulator",
        str(root / "tests/SimulatorKeychainProbe.swift"),
        "-o", str(app / info["CFBundleExecutable"]),
    ], check=True)

    for signed in (False, True):
        if signed:
            subprocess.run([
                sys.executable, str(root / "scripts/package_simulator_app.py"),
                str(app), str(Path(directory) / "probe.zip"),
            ], check=True)
        subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True)
        container = Path(subprocess.check_output([
            "xcrun", "simctl", "get_app_container", device, bundle_id, "data",
        ], text=True).strip())
        output = container / "Documents/keychain-probe.json"
        output.unlink(missing_ok=True)
        try:
            subprocess.run(["xcrun", "simctl", "launch", device, bundle_id], check=True)
        except subprocess.CalledProcessError:
            subprocess.run([
                "xcrun", "simctl", "spawn", device, "log", "show", "--last", "3m",
                "--style", "compact", "--predicate",
                f'eventMessage CONTAINS "{bundle_id}" OR process == "amfid"',
            ], check=False)
            raise
        for _ in range(150):
            if output.exists():
                break
            time.sleep(0.2)
        result = json.loads(output.read_text())
        print("Signed" if signed else "Unsigned", "keychain probe:", result, flush=True)
        expected = 0 if signed else -34018
        assert result == {"add": expected, "read": expected, "delete": expected}, result
        subprocess.run(["xcrun", "simctl", "terminate", device, bundle_id], check=True)
    subprocess.run(["xcrun", "simctl", "uninstall", device, bundle_id], check=True)

print("Simulator packaging regression passed: unsigned fails, signed add/read/delete succeed.")
