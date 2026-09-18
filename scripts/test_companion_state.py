#!/usr/bin/env python3
"""Exercise the app's companion store with an account boundary double."""

from pathlib import Path
import platform
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
views = (root / "FitFight/CompanionViews.swift").read_text()
source = views[:views.index("struct CompanionCharacter: View {")]
source += (root / "tests/CompanionStateTests.swift").read_text()

with tempfile.TemporaryDirectory(prefix="fitfight-companion-tests-") as directory:
    generated = Path(directory) / "CompanionStateTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "companion-state-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(root / "FitFight/Media.swift"), str(root / "FitFight/Profile.swift"),
        str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
