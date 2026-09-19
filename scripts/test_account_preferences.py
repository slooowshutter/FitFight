#!/usr/bin/env python3
"""Run the production preference store against suspended account and API boundaries."""

from pathlib import Path
import re
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
    results = []
    for language, locale, clock in [("en", "en_GB", "NO"), ("fr", "fr_CA", "NO"), ("en", "en_US", "YES")]:
        results.append(subprocess.run([
            str(executable), str(root / "contracts/fixtures/account-preferences.json"),
            "-AppleLanguages", f"({language})", "-AppleLocale", locale,
            "-AppleICUForce24HourTime", clock,
        ], timeout=20).returncode)

    content = (root / "FitFight/ContentView.swift").read_text()
    identity = re.search(r"            signedInApp\n(?:                \.[^\n]+\n)+", content)
    if identity is None:
        raise SystemExit("Could not locate the production signed-in view identity")
    source = (root / "tests/PreferencesViewStateTests.swift").read_text()
    generated = folder / "PreferencesViewStateTests.swift"
    generated.write_text(source.replace("        PRODUCTION_SIGNED_IN_CONTENT", identity.group().rstrip()))
    view_executable = folder / "preference-view-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"),
        str(root / "FitFight/AccountPreferences.swift"), str(generated),
        "-o", str(view_executable),
    ], check=True)
    results.append(subprocess.run([
        str(view_executable), "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
    ], timeout=20).returncode)
    if any(results):
        raise SystemExit("Account preference regression checks failed")
