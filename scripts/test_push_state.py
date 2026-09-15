#!/usr/bin/env python3
"""Exercise production push/session ordering with suspended API and Auth boundaries."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
push = (root / "FitFight/PushNotificationService.swift").read_text()
session = (root / "FitFight/SessionStore.swift").read_text()
content = (root / "FitFight/ContentView.swift").read_text()
harness = (root / "tests/PushStateTests.swift").read_text()
push = push[push.index("@MainActor\nfinal class PushNotificationService:"):]
initializer = session[session.index("    init(listenForSession:"):session.index("    /// Screenshot / preview:")]
listener = session[session.index("    private func listen()"):session.index("    func loadProfile()")]
restore = next(line for line in session.splitlines() if "var isRestoringSession =" in line)
harness = harness.replace("// PUSH_SERVICE", push)
harness = harness.replace("// SESSION_RESTORE_PROPERTY", restore)
harness = harness.replace("// SESSION_BOOTSTRAP_INITIALIZER", initializer)
harness = harness.replace("// SESSION_LISTENER", listener)
app_content = content[content.index("    private var appContent:"):]
assert app_content.index("if session.isRestoringSession") < app_content.index("if session.isSignedIn"), \
    "Auth restoration must be resolved before choosing the welcome or signed-in screen"

with tempfile.TemporaryDirectory(prefix="fitfight-push-tests-") as directory:
    swift = Path(directory) / "PushStateTests.swift"
    executable = Path(directory) / "push-state-tests"
    swift.write_text(harness)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
