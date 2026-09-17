#!/usr/bin/env python3
"""Exercise the app's discovery loading method with controllable API completions."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
api = (root / "FitFight/FitFightAPI.swift").read_text()
method = app[app.index("    private func invalidateFightDiscovery("):app.index("    func setFightSuggested(")]
model = api[api.index("struct FitFightJoinableFight:"):api.index("private struct FitFightJoinableList:")]
source = (root / "tests/FightDiscoveryTests.swift").read_text().replace("// DISCOVERY_METHOD", method)
source += "\n" + model
with tempfile.TemporaryDirectory(prefix="fitfight-discovery-tests-") as directory:
    swift = Path(directory) / "FightDiscoveryTests.swift"
    binary = Path(directory) / "fight-discovery-tests"
    swift.write_text(source)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(root / "FitFight/AppLocalization.swift"), str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
