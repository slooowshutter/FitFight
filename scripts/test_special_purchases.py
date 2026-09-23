#!/usr/bin/env python3
"""Exercise purchase recovery against controllable StoreKit and API boundaries."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "FitFight/SpecialPurchases.swift").read_text()
source = source.replace("import StoreKit\n", "").replace("import UIKit\n", "")
source = source[:source.index("    func requestRefund(")] + "}\n"
source += (root / "tests/SpecialPurchaseTests.swift").read_text()
with tempfile.TemporaryDirectory(prefix="fitfight-special-tests-") as directory:
    generated = Path(directory) / "SpecialPurchaseTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "special-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx14.0",
        str(root / "FitFight/AppLocalization.swift"), str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
