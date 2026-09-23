"""Cut out Marc's supplied editions without redrawing their original RGB artwork.

Run in disposable cloud CI with Pillow, rembg[cpu], and its ISNet model.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter
from rembg import new_session, remove

source = Path(__file__).resolve().parent
catalog = source.parents[3] / "FitFight/Assets.xcassets"
rows = json.loads((source / "limited-editions.json").read_text())
session = new_session("isnet-general-use", providers=["CPUExecutionProvider"])

for row in rows:
    original = Image.open(source / row["preparedSource"]).convert("RGB")
    cutout = remove(original, session=session, alpha_matting=True, alpha_matting_erode_size=1)
    if row["id"] == "limited-pangolin":
        # The pale sock matches the source background; retain its original pixels.
        sock = Image.new("L", original.size)
        ImageDraw.Draw(sock).polygon(
            [(283, 729), (320, 732), (315, 749), (312, 765), (280, 765), (280, 754)],
            fill=255,
        )
        cutout = Image.composite(original.convert("RGBA"), cutout, sock.filter(ImageFilter.GaussianBlur(0.6)))
    alpha = cutout.getchannel("A")
    assert alpha.getextrema() == (0, 255), row["id"]
    assert alpha.getpixel((0, 0)) == 0, row["id"]
    cutout = Image.composite(cutout, Image.new("RGBA", cutout.size), alpha.point(lambda value: 255 if value else 0))
    scale = original.width / row["sourcePixels"][0]
    crop = tuple(round(value * scale) for value in row["avatarCrop"])
    avatar = cutout.crop(crop).resize((300, 300), Image.Resampling.LANCZOS)
    for suffix, image in [("", cutout), ("-avatar", avatar)]:
        folder = catalog / f'Companion-{row["id"]}{suffix}.imageset'
        folder.mkdir(parents=True, exist_ok=True)
        image.save(folder / "image.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "image.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=4) + "\n")
    print(f'Prepared transparent {row["id"]}', flush=True)
