#!/usr/bin/env python3
"""Exercise production chart and HealthKit checkpoint flows with deterministic boundaries."""

import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--emit", type=Path)
args = parser.parse_args()
app = (root / "FitFight/AppModel.swift").read_text()
charts = (root / "FitFight/FightDayCharts.swift").read_text()
health = (root / "FitFight/HealthKitStepAggregates.swift").read_text()
api = (root / "FitFight/FitFightAPI.swift").read_text()
snapshot = (root / "FitFight/FightSnapshot.swift").read_text()
checkpoint = snapshot[snapshot.index("struct FightStepCheckpoint:"):snapshot.index("struct FitFightSnapshot:")]
models = charts[charts.index("private struct FightDayChartSeries:"):charts.index("private func fightDayTickIndices(")]
day_cards = app[app.index("    private static func dayCards("):app.index("    private static func person(from profile:")]
ordering = app[app.index("    private static func orderedStandings("):app.index("\n}\n\nenum LiveFightError")]
read = health[health.index("    static func read("):health.index("    private static func dailyTotals(")]
date_helpers = health[health.index("    private static func dayStamp("):health.rindex("\n}")]
api_models = api[api.index("struct FitFightHealthKitContext:"):api.index("struct FitFightHealthKitStepSyncResult:")]

sources = {
    "FightChartScoreTests": (root / "tests/FightChartScoreTests.swift").read_text()
        .replace("// CHECKPOINT_TYPE", checkpoint)
        .replace("// DAY_SCORE", app[app.index("struct DayScore:"):app.index("struct FightDay:")])
        .replace("// CHART_MODEL", models)
        .replace("    // PRODUCTION_METHODS", day_cards + ordering),
    "HealthKitStepCheckpointTests": (root / "tests/HealthKitStepCheckpointTests.swift").read_text()
        .replace("// API_MODELS", checkpoint + api_models)
        .replace("    // PRODUCTION_METHODS", read + date_helpers),
}
if args.emit:
    args.emit.mkdir(parents=True, exist_ok=True)
    for name, source in sources.items():
        (args.emit / f"{name}.swift").write_text(source)
else:
    with tempfile.TemporaryDirectory(prefix="fitfight-chart-tests-") as directory:
        for name, source in sources.items():
            generated = Path(directory) / f"{name}.swift"
            executable = Path(directory) / name
            generated.write_text(source)
            subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(generated), "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True, timeout=20)
