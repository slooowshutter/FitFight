#!/usr/bin/env python3
"""Run the production Past list and row tap over the real Fight models."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
fights_list = (root / "FitFight/FightsListView.swift").read_text()
activity = (root / "FitFight/FeedActivity.swift").read_text()
models = app[app.index("enum MetricKind:"):app.index("@MainActor\nfinal class AppModel:")]
duration = app[app.index("private func localizedDuration("):app.index("private enum AppModelFixtures")]
link = activity[activity.index("struct FeedPostLink:"):activity.index("struct FeedActivityItem:")]
state = app[app.index("    @Published var tab:"):app.index("    @Published var dailyStatusRecap:")].replace("@Published ", "")
methods = "".join([
    app[app.index("    func fight(id:"):app.index("    func seriesHistory(")],
    app[app.index("    private var canonicalFights:"):app.index("    func formatScore(")],
    app[app.index("    func openFight("):app.index("    func presentDailyStatusRecap(")],
    app[app.index("    private static func fightStatusPriority("):app.index("    static func ordinal(")],
])
row = fights_list[fights_list.index("struct FinishedRow:"):]
tap = row[row.index("Button {") + len("Button {"):row.index("} label:")]

source = (root / "tests/PastRoundsTests.swift").read_text()
source = source.replace("// PRODUCTION_MODELS", models + duration + link)
source = source.replace("    // TAB_STATE", state)
source = source.replace("    // PRODUCTION_METHODS", methods)
source = source.replace("    // PAST_ROW_TAP", tap)

with tempfile.TemporaryDirectory(prefix="fitfight-past-rounds-tests-") as directory:
    generated = Path(directory) / "PastRoundsTests.swift"
    executable = Path(directory) / "past-rounds-tests"
    generated.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "FitFight/AppLocalization.swift"), str(root / "FitFight/RemainingTime.swift"),
        str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
