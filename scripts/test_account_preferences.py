#!/usr/bin/env python3
"""Run the production preference store against suspended account and API boundaries."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="fitfight-preferences-tests-") as directory:
    folder = Path(directory)
    for language, strings in {
        "en": '"Preferences" = "Preferences";\n"test.count" = "%lld choices";\n',
        "fr": '"Preferences" = "Préférences";\n"test.count" = "%lld choix";\n',
    }.items():
        resources = folder / f"{language}.lproj"
        resources.mkdir()
        (resources / "Localizable.strings").write_text(strings)
    executable = folder / "account-preferences-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"),
        str(root / "FitFight/AccountPreferences.swift"),
        str(root / "tests/AccountPreferencesTests.swift"),
        "-o", str(executable),
    ], check=True)
    subprocess.run([
        str(executable), str(root / "contracts/fixtures/account-preferences.json"),
    ], check=True, timeout=20)
