"""Cut Marc’s hiking-goat strip into five native effort imagesets.

Run from the repo root with Python + Pillow. The source PNG is never modified.
"""

import json
from pathlib import Path

from PIL import Image

SOURCE = Path(__file__).resolve().parent
ORIGINAL = SOURCE / "originals/goat-hiking-effort.png"
CATALOG = SOURCE.parents[3] / "FitFight/Assets.xcassets"
# Valleys between the five figures in the 1672×941 source.
SPLITS = [0, 341, 624, 931, 1313]
CANVAS = (352, 400)


def ink_bbox(im, threshold=210, margin=12):
    gray = im.convert("L")
    width, height = gray.size
    pixels = gray.load()
    min_x, min_y, max_x, max_y = width, height, 0, 0
    found = False
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < threshold:
                found = True
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if not found:
        return (0, 0, width, height)
    return (
        max(0, min_x - margin),
        max(0, min_y - margin),
        min(width, max_x + 1 + margin),
        min(height, max_y + 1 + margin),
    )


src = Image.open(ORIGINAL).convert("RGB")
cream = src.getpixel((8, 8))
edges = SPLITS + [src.width]

for index, (x0, x1) in enumerate(zip(edges, edges[1:]), start=1):
    panel = src.crop((x0, 0, x1, src.height))
    cropped = panel.crop(ink_bbox(panel))
    scale = min((CANVAS[0] - 16) / cropped.width, (CANVAS[1] - 16) / cropped.height)
    size = (int(cropped.width * scale), int(cropped.height * scale))
    resized = cropped.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", CANVAS, cream)
    canvas.paste(resized, ((CANVAS[0] - size[0]) // 2, CANVAS[1] - size[1] - 8))
    folder = CATALOG / f"Companion-goat-hiking-{index}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    canvas.save(folder / "image.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "image.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

print("Prepared Companion-goat-hiking-1…5")
