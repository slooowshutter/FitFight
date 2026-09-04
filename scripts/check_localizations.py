#!/usr/bin/env python3
import json
import re
from pathlib import Path


def read_catalog(path: str) -> dict:
    catalog = json.loads(Path(path).read_text())
    if catalog.get("sourceLanguage") != "en":
        raise SystemExit(f"{path}: sourceLanguage must be en")
    for key, entry in catalog["strings"].items():
        if key and "fr" not in entry.get("localizations", {}):
            raise SystemExit(f"{path}: missing French localization for {key!r}")
    return catalog


localizable = read_catalog("FitFight/Localizable.xcstrings")
info_plist = read_catalog("FitFight/InfoPlist.xcstrings")

for key in (
    "CFBundleDisplayName",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
):
    if key not in info_plist["strings"]:
        raise SystemExit(f"FitFight/InfoPlist.xcstrings: missing {key}")

for key in (
    "duration.days",
    "duration.hours",
    "fight.days-left",
    "fight.ends-in-days",
    "fight.hours-left",
    "fight.participant-count",
    "health.steps-today",
):
    entry = localizable["strings"].get(key)
    if not entry:
        raise SystemExit(f"FitFight/Localizable.xcstrings: missing plural key {key}")
    for language in ("en", "fr"):
        plural = entry["localizations"][language]["variations"]["plural"]
        if not {"one", "other"}.issubset(plural):
            raise SystemExit(f"{key}: {language} needs one and other plural forms")

notes = re.findall(r'notes: "((?:[^"\\]|\\.)*)"', Path("FitFight/Changelog.swift").read_text())
for note in notes:
    if note not in localizable["strings"]:
        raise SystemExit(f"FitFight/Localizable.xcstrings: missing changelog note {note!r}")

print(
    f"localizations ok: {len(localizable['strings'])} app strings, "
    f"{len(info_plist['strings'])} Info.plist strings, {len(notes)} release notes"
)
