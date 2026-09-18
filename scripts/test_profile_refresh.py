#!/usr/bin/env python3
"""Exercise You's actual initial and manual refresh actions around a suspended upload."""

from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
you = (root / "FitFight/YouView.swift").read_text()


def body_after(text, marker):
    start = text.index("{", text.index(marker)) + 1
    depth = 1
    for position in range(start, len(text)):
        depth += (text[position] == "{") - (text[position] == "}")
        if depth == 0:
            return text[start:position]
    raise ValueError(f"Unclosed body: {marker}")


initial_task = re.search(r"\.task(?:\(id: session\.authSession\?\.user\.id\))? \{", you).group()
manual = body_after(you, "private var fightsRefresh:")
health = body_after(you, "private var health:")
helper = ""
if "    private func refreshOwnProfile(" in you:
    start = you.index("    private func refreshOwnProfile(")
    opening = you.index("{", start)
    helper = you[start:opening + 1] + body_after(you, "private func refreshOwnProfile(") + "}\n"

source = (root / "tests/ProfileRefreshTests.swift").read_text()
for marker, implementation in {
    "// INITIAL_REFRESH": body_after(you, initial_task),
    "// MANUAL_REFRESH": body_after(manual, "action:"),
    "// HEALTH_REFRESH": body_after(health, "Task"),
    "// REFRESH_HELPER": helper,
}.items():
    source = source.replace(marker, implementation)

with tempfile.TemporaryDirectory(prefix="fitfight-profile-refresh-") as directory:
    generated = Path(directory) / "ProfileRefreshTests.swift"
    binary = Path(directory) / "profile-refresh-tests"
    generated.write_text(source)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(generated), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
