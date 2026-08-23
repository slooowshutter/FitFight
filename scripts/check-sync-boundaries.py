#!/usr/bin/env python3
"""Fail the build if a change violates docs/sync.md persistence / HK / network rules.

Runs on Linux. Does not compile Swift. Allowed-file lists are empty until those
types exist; the forbidden-framework check is live today.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT_ROOT = ROOT / "FitFight"

ALLOWED_HEALTHKIT = {
    SWIFT_ROOT / "Sync" / "ScoreCompiler.swift",
}
ALLOWED_URLSESSION = {
    SWIFT_ROOT / "Sync" / "APIClient.swift",
}
ALLOWED_GRDB = {
    SWIFT_ROOT / "Persistence",
    SWIFT_ROOT / "Sync",
}

FORBIDDEN_FRAMEWORK = re.compile(
    r"\b(import\s+SwiftData|import\s+CloudKit|"
    r"NSPersistentCloudKitContainer|NSUbiquitousKeyValueStore|"
    r"CKRecord|CKContainer|CKDatabase)\b"
)
HEALTHKIT = re.compile(r"\b(import\s+HealthKit|HKHealthStore|HKQuantitySample|HKWorkout)\b")
URLSESSION = re.compile(r"\bURLSession\b")
GRDB = re.compile(r"\bimport\s+GRDB\b")
PREVIEW_IN_MAIN = re.compile(r"AppModel\s*\.\s*preview\s*\(")


def swift_files() -> list[Path]:
    return sorted(SWIFT_ROOT.rglob("*.swift"))


def is_under(path: Path, allowed: set[Path]) -> bool:
    resolved = path.resolve()
    for item in allowed:
        item = item.resolve()
        if item.is_file() and resolved == item:
            return True
        if resolved == item or item in resolved.parents:
            return True
    return False


def main() -> int:
    errors: list[str] = []
    if not SWIFT_ROOT.is_dir():
        print("FitFight/ missing", file=sys.stderr)
        return 1

    main_app = SWIFT_ROOT / "FitFightApp.swift"

    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)

        for match in FORBIDDEN_FRAMEWORK.finditer(text):
            errors.append(
                f"{rel}: '{match.group(1)}' is forbidden. "
                "GRDB replica + outbox only. See docs/sync.md."
            )

        if HEALTHKIT.search(text) and not is_under(path, ALLOWED_HEALTHKIT):
            errors.append(
                f"{rel}: HealthKit only belongs in FitFight/Sync/ScoreCompiler.swift. "
                "See docs/sync.md."
            )

        if URLSESSION.search(text) and not is_under(path, ALLOWED_URLSESSION):
            errors.append(
                f"{rel}: URLSession only belongs in FitFight/Sync/APIClient.swift. "
                "See docs/sync.md."
            )

        if GRDB.search(text) and not is_under(path, ALLOWED_GRDB):
            errors.append(
                f"{rel}: import GRDB is limited to FitFight/Persistence and FitFight/Sync. "
                "Views use AppModel. See docs/sync.md."
            )

        if path.resolve() == main_app.resolve() and PREVIEW_IN_MAIN.search(text):
            errors.append(
                f"{rel}: production @main must not call AppModel.preview(). "
                "Fixtures are screenshots / SwiftUI previews only."
            )

    if errors:
        print("sync boundary check failed:", file=sys.stderr)
        for line in errors:
            print(f"  {line}", file=sys.stderr)
        return 1

    print("sync boundaries ok", len(swift_files()), "swift files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
