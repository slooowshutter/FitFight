#!/usr/bin/env python3
"""Exercise production Google sign-in with suspended Google and Supabase boundaries."""

from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
session = (root / "FitFight/SessionStore.swift").read_text()
config = (root / "FitFight/GoogleSignInConfig.swift").read_text().replace("import GoogleSignIn\n", "")
clients = (root / "web/lib/google/google-clients.ts").read_text()
method = session[session.index("    func signInWithGoogle("):session.index("    #if DEBUG\n")]
errors = session[session.index("    static func signInFailureMessage("):session.index("    static func isValidHandle(")]
harness = (root / "tests/GoogleSignInTests.swift").read_text()
harness = harness.replace("// GOOGLE_SIGN_IN_METHOD", method + errors)
harness += "\n" + config
plist = plistlib.loads((root / "FitFight/Info.plist").read_bytes())
schemes = [scheme for entry in plist["CFBundleURLTypes"] for scheme in entry["CFBundleURLSchemes"]]
for client in (
    "428975685987-6j9128tgf2k67pkf5tlsdbs58md0b38u",
    "1060235196761-nuoouoc4envuhkpo4kpdfpdg8u20tlq4",
):
    assert "com.googleusercontent.apps." + client in schemes, "Missing Google callback scheme"
    assert client in config
    assert client in clients

with tempfile.TemporaryDirectory(prefix="fitfight-google-tests-") as directory:
    source = Path(directory) / "GoogleSignInTests.swift"
    executable = Path(directory) / "google-sign-in-tests"
    source.write_text(harness)
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        str(source), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
