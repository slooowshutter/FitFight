#!/usr/bin/env python3
"""Exercise production onboarding progress and session isolation on the hosted runner."""

from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
session = (root / "FitFight/SessionStore.swift").read_text()
methods = session[session.index("    var needsOnboarding:"):session.index("    var needsHealthOnboarding:")]
keys = "\n".join(re.findall(r'    private static let (?:needsHealthKey|needsNotificationKey|needsRequestsKey|needsSuggestedPrefix|firstFightPrefix) = .*', session))
source = (root / "tests/OnboardingStateTests.swift").read_text()
source = source.replace("    // SESSION_KEYS", keys)
source = source.replace("    // SESSION_METHODS", methods.replace("UserDefaults.standard", "defaults"))
with tempfile.TemporaryDirectory(prefix="fitfight-onboarding-tests-") as directory:
    generated = Path(directory) / "OnboardingStateTests.swift"
    executable = Path(directory) / "onboarding-state-tests"
    generated.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/FirstFightOnboarding.swift"), str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
