#!/usr/bin/env python3
"""Exercise production refresh ordering and Realtime lifecycle with suspended boundaries."""

from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--emit", type=Path)
args = parser.parse_args()
app = (root / "FitFight/AppModel.swift").read_text()
listener = (root / "FitFight/FightLiveUpdates.swift").read_text()
listener = "\n".join(line for line in listener.splitlines() if not line.startswith("import "))
snapshot = app[app.index("    func refreshFromServer(\n"):app.index("    /// Locks Start fight immediately")]
cache = app[app.index("    func restoreCachedFights("):app.index("    func refreshFights(")]

# A failed upload cannot publish local totals into the standings before confirmation.
assert "applyLocalHealthKitScores" not in app
assert "onLocalAggregates" not in (root / "FitFight/HealthKitStepsStore.swift").read_text()

sources = {
    "FightLiveUpdatesTests": (root / "tests/FightLiveUpdatesTests.swift").read_text() + "\n" + listener,
    "FightSnapshotStateTests": (root / "tests/FightSnapshotStateTests.swift").read_text().replace(
        "    // PRODUCTION_METHODS", snapshot + cache
    ),
}
if args.emit:
    args.emit.mkdir(parents=True, exist_ok=True)
    for name, source in sources.items():
        (args.emit / f"{name}.swift").write_text(source)
else:
    with tempfile.TemporaryDirectory(prefix="fitfight-live-tests-") as directory:
        for name, source in sources.items():
            generated = Path(directory) / f"{name}.swift"
            executable = Path(directory) / name
            generated.write_text(source)
            subprocess.run([
                "swiftc", "-swift-version", "5", "-parse-as-library", str(root / "FitFight/AppLocalization.swift"), str(generated), "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True, timeout=20)
