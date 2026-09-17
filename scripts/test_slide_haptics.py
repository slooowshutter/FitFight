#!/usr/bin/env python3
"""Exercise the production slide engine with recording haptic hardware boundaries."""

import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--emit", type=Path)
args = parser.parse_args()
engine = (root / "FitFight/DesignSystem/SlideHaptics.swift").read_text()
engine = "\n".join(line for line in engine.splitlines() if not line.startswith("import "))
components = (root / "FitFight/DesignSystem/Components.swift").read_text()
gesture = components[components.index("    private func slideGesture("):components.index("\n}\n\n/// Dashed")]
recipe = components[components.index("    private var resolvedRecipe:"):components.index("    private let knobSize:")]
lab = (root / "FitFight/SlideHapticsLabView.swift").read_text()
settings = lab[lab.index("    private var settings:"):lab.index("    private var rumbleControls:")]
source = (root / "tests/SlideHapticTests.swift").read_text().replace("    // PRODUCTION_GESTURE", gesture).replace("    // PRODUCTION_RECIPE", recipe).replace("    // PRODUCTION_SETTINGS", settings) + "\n" + engine

if args.emit:
    args.emit.mkdir(parents=True, exist_ok=True)
    (args.emit / "SlideHapticTests.swift").write_text(source)
else:
    with tempfile.TemporaryDirectory(prefix="fitfight-haptic-tests-") as directory:
        generated = Path(directory) / "SlideHapticTests.swift"
        executable = Path(directory) / "SlideHapticTests"
        generated.write_text(source)
        subprocess.run([
            "swiftc", "-swift-version", "5", "-parse-as-library", str(generated), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True, timeout=20)
