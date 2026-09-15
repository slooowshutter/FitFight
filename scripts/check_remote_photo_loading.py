#!/usr/bin/env python3
"""Run the actual SwiftUI image task with controlled asynchronous image responses."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "FitFight/RemoteImage.swift").read_text()
marker = '.task(id: url?.absoluteString ?? "") {'
start = source.index(marker) + len(marker)
depth = 1
end = start
while depth:
    if source[end] == "{":
        depth += 1
    elif source[end] == "}":
        depth -= 1
    end += 1

harness = (root / "tests/RemotePhotoLoadingTests.swift").read_text()
harness = harness.replace("// REMOTE_PHOTO_TASK", source[start:end - 1])
with tempfile.TemporaryDirectory(prefix="fitfight-photo-tests-") as directory:
    swift = Path(directory) / "RemotePhotoLoadingTests.swift"
    binary = Path(directory) / "remote-photo-tests"
    swift.write_text(harness)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
