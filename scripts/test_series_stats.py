#!/usr/bin/env python3
"""Run the History leaderboard and records over the real Fight models."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
models = app[app.index("enum MetricKind:"):app.index("@MainActor\nfinal class AppModel:")]
duration = app[app.index("private func localizedDuration("):app.index("private enum AppModelFixtures")]
source = (root / "tests/SeriesStatsTests.swift").read_text()
source = source.replace("// PRODUCTION_MODELS", models + duration)

with tempfile.TemporaryDirectory(prefix="fitfight-series-stats-tests-") as directory:
    generated = Path(directory) / "SeriesStatsTests.swift"
    executable = Path(directory) / "series-stats-tests"
    generated.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"), str(root / "FitFight/RemainingTime.swift"),
        str(root / "FitFight/SeriesStats.swift"), str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
