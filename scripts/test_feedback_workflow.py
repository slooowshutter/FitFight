#!/usr/bin/env python3
"""Compile real feedback DTOs and frozen released decoders on GitHub-hosted macOS."""

from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
api = (root / "FitFight/FitFightAPI.swift").read_text()
metadata = (root / "FitFight/FeedbackClientMetadata.swift").read_text()
source = "import Foundation\n"
source += api[api.index("enum FeedbackWorkflowStatus:"):api.index("struct FitFightReferralLink:")]
source += metadata[metadata.index("struct FitFightFeedbackMetadata:"):metadata.index("    @MainActor")]
source += "}\n" + metadata[metadata.index("extension FitFightFeedbackMetadata: Codable"):]
source += (root / "tests/FeedbackWorkflowTests.swift").read_text()

with tempfile.TemporaryDirectory(prefix="fitfight-feedback-tests-") as directory:
    generated = Path(directory) / "FeedbackWorkflowTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "feedback-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(root / "FitFight/Media.swift"),
        str(root / "tests/fixtures/FeedbackBuild201Models.swift"),
        str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), str(root / "contracts/fixtures")], check=True, timeout=15)
