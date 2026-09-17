#!/usr/bin/env python3
"""Run the real Profile actions, navigation resolution, and rematch preparation in cloud CI."""

from pathlib import Path
import argparse
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--emit", type=Path)
args = parser.parse_args()
app = (root / "FitFight/AppModel.swift").read_text()
profile = (root / "FitFight/ProfileSheet.swift").read_text()
content = (root / "FitFight/ContentView.swift").read_text()
detail = (root / "FitFight/FightDetailView.swift").read_text()
composer = (root / "FitFight/FightComposer.swift").read_text()
new_fight = (root / "FitFight/NewFightView.swift").read_text()
feed = (root / "FitFight/FeedView.swift").read_text()

state = app[app.index("    @Published var tab:"):app.index("    @Published var dailyStatusRecap:")].replace("@Published ", "")
selection = app[app.index("    func fight(id:"):app.index("    func seriesHistory(for fight:")]
priority = app[app.index("    private static func fightStatusPriority("):app.index("    private static func ordinal(")]
opening = app[app.index("    func openFight"):app.index("    func presentDailyStatusRecap(")]
history = profile[profile.index("                ForEach(store.history)"):]
history_action = history[history.index("                        Button {") + len("                        Button {"):history.index("                        } label:")]
destination = re.search(r"if let fight = (.+) \{", content[content.index(".navigationDestination(for: String.self)"):]).group(1)
feed_action = re.search(r"\{ (model\.openFight.+) \}", feed).group(1)
display = detail[detail.index("    private var fight:"):detail.index("    private var panes:")].replace("private var fight:", "var fight:")
prepare = new_fight[new_fight.index("    private func applyProfileChallenge("):new_fight.index("    private var duration:")].replace("private func", "func")
end_date = composer[composer.index("    static func endDate("):composer.index("\n}\n\nstruct FightComposerMetricPage:")]

source = (root / "tests/ProfileNavigationTests.swift").read_text()
for marker, implementation in {
    "// MODEL_STATE": state,
    "// MODEL_METHODS": selection + priority + opening,
    "// HISTORY_ACTION": history_action,
    "// FEED_ACTION": feed_action,
    "// DESTINATION": "return " + destination,
    "// DETAIL_SELECTION": display,
    "// PREPARE_REMATCH": prepare,
    "// END_DATE": end_date,
}.items():
    source = source.replace(marker, implementation)

if args.emit:
    args.emit.write_text(source)
else:
    with tempfile.TemporaryDirectory(prefix="fitfight-profile-navigation-") as directory:
        generated = Path(directory) / "ProfileNavigationTests.swift"
        binary = Path(directory) / "profile-navigation-tests"
        generated.write_text(source)
        subprocess.run([
            "swiftc", "-swift-version", "5", "-parse-as-library",
            str(root / "FitFight/SharedProfile.swift"), str(generated), "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary)], check=True, timeout=20)
