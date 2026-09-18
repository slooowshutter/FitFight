#!/usr/bin/env python3
"""Run actual onboarding actions and Profile-to-round navigation on hosted macOS."""

from pathlib import Path
import platform
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
onboarding = (root / "FitFight/SuggestedFightsOnboardingView.swift").read_text()
profile = (root / "FitFight/ProfileSheet.swift").read_text()
content = (root / "FitFight/ContentView.swift").read_text()
detail = (root / "FitFight/FightDetailView.swift").read_text()
api = (root / "FitFight/FitFightAPI.swift").read_text()

sync_start = re.search(r"^    (?:private )?func syncStepsAfterMembershipChange\(", app, re.M).start()
profile_rows = profile[profile.index("ForEach(store.history)"):profile.index("if store.nextCursor != nil")]
history_tap = profile_rows[profile_rows.index("Button {") + len("Button {"):profile_rows.index("} label:")]
destination = content[content.index(".navigationDestination(for: String.self)"):]
destination_lookup = destination.split("if let fight = ", 1)[1].split(" {", 1)[0]

source = (root / "tests/ProfileInteractionTests.swift").read_text()
source = source.replace("    // ONBOARDING_METHODS", onboarding[
    onboarding.index("    private func finish()"):onboarding.index("\n}\n\nstruct SuggestedFightOffer")
])
source = source.replace("    // APP_METHODS", "\n".join([
    app[sync_start:app.index("    private func joinPendingFight(")],
    app[app.index("    func fight(id:"):app.index("    func seriesHistory(")],
    app[app.index("    func openFightFromFeed("):app.index("    func presentDailyStatusRecap(")],
    app[app.index("    private static func fightStatusPriority("):app.index("    private static func ordinal(")],
]))
source = source.replace("    // TAB_STATE", app[
    app.index("    @Published var tab:"):app.index("    @Published var openFightID:")
].replace("@Published ", ""))
source = source.replace("        // HISTORY_TAP", history_tap)
source = source.replace("        // DESTINATION_LOOKUP", destination_lookup)
source = source.replace("    // DETAIL_FIGHT", detail[
    detail.index("    private var fight:"):detail.index("    private var panes:")
])
source += "\n" + api[api.index("struct FitFightJoinableFight:"):api.index("private struct FitFightJoinableList:")]

with tempfile.TemporaryDirectory(prefix="fitfight-profile-interactions-") as directory:
    swift = Path(directory) / "ProfileInteractionTests.swift"
    binary = Path(directory) / "profile-interaction-tests"
    swift.write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(swift), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
