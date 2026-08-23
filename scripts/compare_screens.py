#!/usr/bin/env python3
"""Put each rendered screen next to the design mock it is meant to reproduce.

The renders come out of the Screenshots workflow; the mocks live in
docs/design/source/screenshots/app. The mock is a browser screenshot inside a phone
frame, so its content sits lower than ours by the height of its fake status bar. We
find that shift per screen by picking the vertical offset with the smallest pixel
difference, then write a side-by-side and a difference map.

Usage: python3 scripts/compare_screens.py <renders-dir> <output-dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
MOCKS = REPO / "docs/design/source/screenshots/app"

# render file -> design mock. The mock is 788x1706 with a 1px phone frame each side.
PAIRS = [
    ("01-fights.png", "001-fights-list-top.png"),
    ("02-fight-detail.png", "003-fight-winner-takes-all-top.png"),
    ("03-fight-invited.png", "012-fight-invited-not-joined.png"),
    ("04-new.png", "014-new-top.png"),
    ("05-requests.png", "028-requests-top.png"),
    ("06-you.png", "033-you-top.png"),
]

BAND = (150, 1450)  # the part of the screen both sides actually share


def load_mock(name):
    return np.asarray(Image.open(MOCKS / name).convert("RGB").crop((1, 0, 787, 1706))).astype(int)


def best_offset(mock, render):
    y0, y1 = BAND
    best = None
    for off in range(0, 70):
        if y1 - off > render.shape[0]:
            continue
        score = np.abs(mock[y0:y1] - render[y0 - off:y1 - off]).mean()
        if best is None or score < best[1]:
            best = (off, score)
    return best


def main(renders_dir, out_dir):
    renders = Path(renders_dir)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    worst = 0.0
    for render_name, mock_name in PAIRS:
        render_path = renders / render_name
        if not render_path.exists():
            print(f"skip {render_name}: not rendered")
            continue
        mock = load_mock(mock_name)
        render = np.asarray(Image.open(render_path).convert("RGB")).astype(int)
        off, score = best_offset(mock, render)
        worst = max(worst, score)
        y0, y1 = BAND
        stem = render_name.replace(".png", "")

        left = Image.fromarray(mock[y0:y1].astype(np.uint8))
        right = Image.fromarray(render[y0 - off:y1 - off].astype(np.uint8))
        sheet = Image.new("RGB", (786 * 2 + 12, y1 - y0), (255, 0, 255))
        sheet.paste(left, (0, 0))
        sheet.paste(right, (798, 0))
        sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
        sheet.save(out / f"{stem}-side-by-side.png")

        delta = np.abs(mock[y0:y1] - render[y0 - off:y1 - off]).max(axis=2)
        Image.fromarray(np.clip(delta * 3, 0, 255).astype(np.uint8)).save(out / f"{stem}-diff.png")
        print(f"{stem:20s} offset {off:2d}  mean difference {score:5.2f}")
    print(f"worst mean difference {worst:.2f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
