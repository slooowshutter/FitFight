#!/usr/bin/env python3
"""Exercise current and frozen notification models on GitHub-hosted macOS."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
api = (root / "FitFight/FitFightAPI.swift").read_text()
source = "import Foundation\n"
source += api[api.index("struct FitFightNotificationPreferences:"):api.index("private struct FitFightDeviceInstallationBody:")]
source += (root / "tests/fixtures/NotificationLegacyModels.swift").read_text()
extension = (root / "FitFightNotificationService/NotificationService.swift").read_text()
source += "enum NotificationImagePolicy {\n"
source += extension[extension.index("    static func isAllowedImageURL"):extension.index("    private func finish")]
source += "}\n" + (root / "tests/NotificationPreferencesTests.swift").read_text()
with tempfile.TemporaryDirectory(prefix="fitfight-notifications-") as directory:
    generated = Path(directory) / "NotificationTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "notification-tests"
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-target",
                    f"{platform.machine()}-apple-macosx14.0", str(generated), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
