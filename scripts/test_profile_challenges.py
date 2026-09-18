#!/usr/bin/env python3
"""Exercise the real rematch composer method on GitHub-hosted macOS."""

from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
view = (root / "FitFight/NewFightView.swift").read_text()
composer = (root / "FitFight/FightComposer.swift").read_text()
method = view[view.index("    private func applyProfileChallenge("):view.index("    private var duration:")]
source = (root / "tests/ProfileChallengeTests.swift").read_text().replace("// PROFILE_CHALLENGE_METHOD", method)
source += "\n" + view[view.index("enum NewFightOpening"):view.index("struct NewFightView:")]
source += "\nenum FightComposer {\n" + composer[composer.index("    static func endDate("):composer.index("\n}\n\nstruct FightComposerMetricPage:")] + "\n}\n"
with tempfile.TemporaryDirectory(prefix="fitfight-profile-challenge-tests-") as directory:
    swift = Path(directory) / "ProfileChallengeTests.swift"
    binary = Path(directory) / "profile-challenge-tests"
    swift.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(root / "FitFight/SharedProfile.swift"), str(swift), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
