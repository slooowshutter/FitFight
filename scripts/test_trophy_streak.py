#!/usr/bin/env python3
"""Run the production series trophy streak over the real Fight models."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
models = app[app.index("enum MetricKind:"):app.index("@MainActor\nfinal class AppModel:")]
duration = app[app.index("private func localizedDuration("):app.index("private enum AppModelFixtures")]
methods = app[app.index("    func seriesHistory(for fight:"):app.index("    func fightResult(for fight:")]
source = (root / "tests/TrophyStreakTests.swift").read_text()
source = source.replace("// PRODUCTION_MODELS", models + duration)
source = source.replace("    // PRODUCTION_METHODS", methods)

with tempfile.TemporaryDirectory(prefix="fitfight-trophy-tests-") as directory:
    generated = Path(directory) / "TrophyStreakTests.swift"
    executable = Path(directory) / "trophy-streak-tests"
    generated.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"), str(root / "FitFight/RemainingTime.swift"),
        str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
