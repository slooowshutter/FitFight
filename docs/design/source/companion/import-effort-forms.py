"""Download the five Blend effort forms per companion into native imagesets.

Run from the repo root with Python + Pillow. `effort-forms.json` maps each
StockCompanion raw value to its five image URLs, resting first.
"""

import io
import json
import urllib.request
from pathlib import Path

from PIL import Image

SOURCE = Path(__file__).resolve().parent
CATALOG = SOURCE.parents[3] / "FitFight/Assets.xcassets"
CANVAS = (352, 400)
MARGIN = 8

for animal, urls in json.loads((SOURCE / "effort-forms.json").read_text()).items():
    forms = [Image.open(io.BytesIO(urllib.request.urlopen(url).read())).convert("RGBA") for url in urls]
    # One shared crop and scale keeps the seated pose smaller than the standing ones.
    boxes = [form.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox() for form in forms]
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    width, height = crop[2] - crop[0], crop[3] - crop[1]
    scale = min((CANVAS[0] - 2 * MARGIN) / width, (CANVAS[1] - 2 * MARGIN) / height)
    size = (round(width * scale), round(height * scale))
    for index, form in enumerate(forms, start=1):
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.paste(form.crop(crop).resize(size, Image.Resampling.LANCZOS), ((CANVAS[0] - size[0]) // 2, CANVAS[1] - size[1] - MARGIN))
        folder = CATALOG / f"Companion-{animal}-effort-{index}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        canvas.save(folder / "image.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "image.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=4) + "\n")
