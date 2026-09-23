#!/usr/bin/env python3
"""Run the production generation state with isolated account and API boundaries."""

from pathlib import Path
import os
import platform
import subprocess
import tempfile

if os.environ.get("CI") != "true":
    raise SystemExit("Run native generation checks on GitHub-hosted macOS only")

root = Path(__file__).resolve().parents[1]
store = (root / "FitFight/AICompanionStore.swift").read_text()
store = store.replace("import SwiftUI", "import Foundation")
store = store.replace(": ObservableObject", "").replace("@Published ", "")
source = store + "\n" + (root / "tests/AICompanionStateTests.swift").read_text()

with tempfile.TemporaryDirectory(prefix="fitfight-ai-tests-") as directory:
    generated = Path(directory) / "AICompanionStateTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "ai-companion-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx14.0",
        str(root / "FitFight/AppLocalization.swift"),
        str(root / "FitFight/Media.swift"), str(root / "FitFight/Profile.swift"),
        str(root / "FitFight/AIWorkflowRequest.swift"), str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), str(root / "contracts/fixtures")], check=True, timeout=30)
