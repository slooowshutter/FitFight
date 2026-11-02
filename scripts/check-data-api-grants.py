#!/usr/bin/env python3
"""Fail when a public table, view, or sequence is created without a Data API GRANT.

Supabase no longer grants anon, authenticated, or service_role on new public
objects. A later migration may grant the object. To keep it off the Data API,
put this comment in the migration that creates it:

    -- data-api-grants: opt-out public.name
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"

OPT_OUT = re.compile(
    r"--\s*data-api-grants:\s*opt-out\s+public\.([a-zA-Z_][a-zA-Z0-9_]*)",
    re.IGNORECASE,
)
CREATE = re.compile(
    r"\bcreate\s+(?:or\s+replace\s+)?(?:unlogged\s+|temp\s+|temporary\s+)?"
    r"(table|view|sequence)\s+(?:if\s+not\s+exists\s+)?public\.([a-zA-Z_][a-zA-Z0-9_]*)",
    re.IGNORECASE,
)
DROP = re.compile(
    r"\bdrop\s+(table|view|sequence)\s+(?:if\s+exists\s+)?public\.([a-zA-Z_][a-zA-Z0-9_]*)",
    re.IGNORECASE,
)
GRANT_ALL_TABLES = re.compile(r"\ball\s+tables\s+in\s+schema\s+public\b", re.IGNORECASE)
GRANT_ALL_SEQUENCES = re.compile(
    r"\ball\s+sequences\s+in\s+schema\s+public\b", re.IGNORECASE
)
PUBLIC_NAME = re.compile(r"\bpublic\.([a-zA-Z_][a-zA-Z0-9_]*)", re.IGNORECASE)


def strip_sql(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    sql = re.sub(r"--.*?$", " ", sql, flags=re.MULTILINE)
    out: list[str] = []
    index = 0
    while index < len(sql):
        if sql[index] == "$":
            tag = re.match(r"\$[A-Za-z0-9_]*\$", sql[index:])
            if tag:
                marker = tag.group(0)
                end = sql.find(marker, index + len(marker))
                if end != -1:
                    out.append(" ")
                    index = end + len(marker)
                    continue
        out.append(sql[index])
        index += 1
    return "".join(out)


def missing_grants(files: list[tuple[str, str]]) -> list[str]:
    pending: dict[str, str] = {}
    for name, text in files:
        opted_out = {item.lower() for item in OPT_OUT.findall(text)}
        for statement in strip_sql(text).split(";"):
            stripped = statement.strip()
            if not stripped:
                continue
            for match in DROP.finditer(stripped):
                pending.pop(match.group(2).lower(), None)
            for match in CREATE.finditer(stripped):
                kind, object_name = match.group(1).lower(), match.group(2).lower()
                if object_name in opted_out:
                    pending.pop(object_name, None)
                    continue
                pending[object_name] = f"{kind} public.{object_name} in {name}"
            if not re.match(r"grant\b", stripped, re.IGNORECASE):
                continue
            if GRANT_ALL_TABLES.search(stripped):
                for object_name, label in list(pending.items()):
                    if label.startswith("table "):
                        pending.pop(object_name, None)
            if GRANT_ALL_SEQUENCES.search(stripped):
                for object_name, label in list(pending.items()):
                    if label.startswith("sequence "):
                        pending.pop(object_name, None)
            for object_name in PUBLIC_NAME.findall(stripped):
                pending.pop(object_name.lower(), None)
    return sorted(pending.values())


def selftest() -> None:
    assert missing_grants([
        ("a.sql", "create table public.foo (id uuid); grant select on public.foo to authenticated;"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create table public.foo (id uuid);"),
    ]) == ["table public.foo in a.sql"]
    assert missing_grants([
        ("a.sql", "-- data-api-grants: opt-out public.foo\ncreate table public.foo (id uuid);"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create table public.foo (id uuid); grant all on all tables in schema public to service_role;"),
    ]) == []
    assert missing_grants([
        ("a.sql", "grant all on all tables in schema public to service_role; create table public.foo (id uuid);"),
    ]) == ["table public.foo in a.sql"]
    assert missing_grants([
        ("a.sql", "create table private.foo (id uuid);"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create table public.foo (id uuid); drop table public.foo;"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create table public.foo (id uuid);"),
        ("b.sql", "grant select on table public.foo to service_role;"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create sequence public.foo_id_seq; grant usage, select on all sequences in schema public to service_role;"),
    ]) == []
    assert missing_grants([
        ("a.sql", "create view public.foo as select 1;"),
    ]) == ["view public.foo in a.sql"]


def main() -> int:
    selftest()
    if not MIGRATIONS.is_dir():
        print("no supabase/migrations directory", file=sys.stderr)
        return 1
    files = [
        (path.name, path.read_text())
        for path in sorted(MIGRATIONS.glob("*.sql"))
    ]
    missing = missing_grants(files)
    if missing:
        print("Public objects created without a Data API GRANT:")
        for item in missing:
            print(f"  {item}")
        print(
            "Grant the role in that migration or a later one, or add "
            "`-- data-api-grants: opt-out public.name` in the creating file."
        )
        return 1
    print("data api grants ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
