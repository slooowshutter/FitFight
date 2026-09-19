#!/usr/bin/env python3
"""Exercise cached Fight copy through the production language-change handler."""

import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
scene = (root / "FitFight/FitFightApp.swift").read_text()
models = app[app.index("enum MetricKind:"):app.index("extension FFAvatar {")]
models += app[app.index("struct Standing:"):app.index("@MainActor\nfinal class AppModel:")]
methods = app[app.index("    func removeCachedFights("):app.index("    /// Locks Start fight immediately")]
methods += app[app.index("    func restoreCachedFights("):app.index("    func refreshFights(")]
methods += app[app.index("    func formatScore("):app.index("    func formatLastSync(")]
methods += app[app.index("    private static func dayCards("):app.index("    func openFight(")]
methods += app[app.index("    private static func mapFight("):app.index("\n}\n\nenum LiveFightError")]
duration = app[app.index("private func localizedDuration("):app.index("private enum AppModelFixtures")]
handler = scene.split(".onChange(of: preferences.value.language) { _, _ in\n", 1)[1].split("\n                }", 1)[0]
handler = handler.replace("                    Task {", "                    changeTask = Task {")
source = (root / "tests/FightLocalizationTests.swift").read_text()
source = source.replace("// PRODUCTION_MODELS", models + duration)
source = source.replace("    // PRODUCTION_METHODS", methods)
source = source.replace("        // PRODUCTION_LANGUAGE_CHANGE", handler)
catalog = json.loads((root / "FitFight/Localizable.xcstrings").read_text())["strings"]

with tempfile.TemporaryDirectory(prefix="fitfight-localization-tests-") as directory:
    folder = Path(directory)
    for language in ["en", "fr"]:
        resources = folder / f"{language}.lproj"
        resources.mkdir()
        strings = []
        for key, entry in catalog.items():
            translation = entry.get("localizations", {}).get(language, {}).get("stringUnit")
            if translation:
                strings.append(f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(translation["value"], ensure_ascii=False)};')
        (resources / "Localizable.strings").write_text("\n".join(strings))
    generated = folder / "FightLocalizationTests.swift"
    generated.write_text(source)
    executable = folder / "fight-localization-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"),
        str(root / "FitFight/RemainingTime.swift"), str(root / "FitFight/FightSnapshot.swift"),
        str(root / "FitFight/Profile.swift"), str(root / "FitFight/Media.swift"),
        str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"], check=True, timeout=20)
