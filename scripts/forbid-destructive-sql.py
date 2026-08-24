#!/usr/bin/env python3
"""Block migrations that can wipe hosted data unless Marc explicitly allows them."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"

FORBIDDEN = re.compile(
    r"""
    \b(
        drop\s+table\b
        | drop\s+schema\b
        | drop\s+database\b
        | truncate\s+
        | alter\s+table\b[\s\S]{0,80}?\bdrop\s+column\b
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)


def without_comments(sql: str) -> str:
    sql = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
    return re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)


def main() -> int:
    if not MIGRATIONS.is_dir():
        print("no supabase/migrations directory", file=sys.stderr)
        return 1

    blocked: list[str] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        text = path.read_text()
        if re.search(r"(?m)^--\s*allow-destructive\b", text):
            continue
        if FORBIDDEN.search(without_comments(text)):
            blocked.append(path.name)

    if blocked:
        print("Destructive SQL is blocked:", ", ".join(blocked))
        print(
            "Use an additive migration. If Marc asked to drop data in this chat, "
            "the file must start with: -- allow-destructive"
        )
        return 1

    print("migrations ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
