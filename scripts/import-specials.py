#!/usr/bin/env python3
"""Turn the generated Specials art into the app's imagesets.

Usage: python3 scripts/import-specials.py [SOURCE]

SOURCE (default `.context/specials-final`) holds one folder per Special id from
docs/design/source/companion/limited-editions.json, each with portrait.png and
effort-1.png to effort-5.png on transparent backgrounds. For every Special this
writes Companion-<id> (portrait), Companion-<id>-avatar (300x300 head crop) and
Companion-<id>-effort-1..5. Portrait and efforts share the 352x400 canvas used by
the regular animals: 8px margin, bottom anchored, transparent.

Missing art is filled with a placeholder and reported: a missing effort reuses the
portrait; a missing portrait uses the chosen selection image recorded in the source
workspace's specials-v2.json "final" section. Rerun once the art is complete.
"""

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "FitFight/Assets.xcassets"
CANVAS = (352, 400)
MARGIN = 8
AVATAR = 300

source = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / ".context/specials-final").resolve()
rows = json.loads((ROOT / "docs/design/source/companion/limited-editions.json").read_text())
workspace = source.parent.parent
selection = workspace / "docs/design/source/companion/specials-v2.json"
chosen = {}
if selection.exists():
    for series in json.loads(selection.read_text())["final"]["series"]:
        for special in series["specials"]:
            chosen["limited-" + special["id"].removeprefix("special-")] = workspace / special["file"]


def save(image, name):
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / "image.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "image.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=4) + "\n")


def opaque_box(image):
    return image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()


def fit(images):
    """One shared crop and scale, so poses of one animal keep their relative size."""
    boxes = [opaque_box(image) for image in images]
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    width, height = crop[2] - crop[0], crop[3] - crop[1]
    scale = min((CANVAS[0] - 2 * MARGIN) / width, (CANVAS[1] - 2 * MARGIN) / height)
    size = (round(width * scale), round(height * scale))
    fitted = []
    for image in images:
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.paste(image.crop(crop).resize(size, Image.Resampling.LANCZOS), ((CANVAS[0] - size[0]) // 2, CANVAS[1] - size[1] - MARGIN))
        fitted.append(canvas)
    return fitted


placeholders = []
for row in rows:
    special = row["id"]
    portrait_path = source / special / "portrait.png"
    if not portrait_path.exists():
        portrait_path = chosen.get(special)
        if not portrait_path or not portrait_path.exists():
            sys.exit(f"{special}: no portrait.png and no selection image to stand in")
        placeholders.append(f"{special}/portrait.png")
    portrait = Image.open(portrait_path).convert("RGBA")
    efforts = []
    for index in range(1, 6):
        path = source / special / f"effort-{index}.png"
        if path.exists():
            efforts.append(Image.open(path).convert("RGBA"))
        else:
            efforts.append(portrait)
            placeholders.append(f"{special}/effort-{index}.png")

    save(fit([portrait])[0], f"Companion-{special}")
    for index, image in enumerate(fit(efforts), start=1):
        save(image, f"Companion-{special}-effort-{index}")

    # The head is the top of the figure: a square as wide as the figure's upper part, from its top edge.
    left, top, right, bottom = opaque_box(portrait)
    upper = portrait.crop((left, top, right, top + round((bottom - top) * 0.4)))
    upper_left, _, upper_right, _ = opaque_box(upper)
    side = round((upper_right - upper_left) * 1.08)
    centre = left + (upper_left + upper_right) / 2
    pad = round(side * 0.04)
    box = (round(centre - side / 2), top - pad, round(centre + side / 2), top - pad + side)
    head = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    head.paste(portrait.crop(box), (0, 0))
    save(head.resize((AVATAR, AVATAR), Image.Resampling.LANCZOS), f"Companion-{special}-avatar")
    print(f"Imported {special}", flush=True)

if placeholders:
    print(f"PLACEHOLDERS ({len(placeholders)}): rerun when the art is complete")
    for item in placeholders:
        print("  " + item)
