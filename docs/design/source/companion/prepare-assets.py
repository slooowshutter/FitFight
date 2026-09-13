"""Extract the approved atlas without adjacent characters or detached alpha noise.

Run from the repo root with Python + Pillow. Originals are never modified.
"""

import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

SOURCE = Path(__file__).resolve().parent
CATALOG = SOURCE.parents[3] / "FitFight/Assets.xcassets"
CHARACTERS = [
    ("badger", (206, 111)), ("raccoon", (554, 113)),
    ("red-panda", (865, 108)), ("otter", (1192, 97)),
    ("rabbit", (202, 485)), ("fox", (546, 477)),
    ("bear", (860, 481)), ("boar", (1195, 493)),
    ("sloth", (204, 849)), ("dog", (539, 826)),
    ("goat", (868, 857)), ("turtle", (1185, 850)),
]

atlas = Image.open(SOURCE / "originals/atlas.png").convert("RGBA")
alpha = atlas.getchannel("A")
manifest = {
    "source": "../kit/companion-app-proposal.html#artwork",
    "atlas": {"file": "originals/atlas.png", "pixels": list(atlas.size), "transparent": True},
    "extraction": "Connected alpha >= 96 from the face, expanded 4 px to retain original antialiasing. Detached atlas noise and adjacent characters excluded. Full body and ground fit within a padded 352 x 400 canvas; no rescaling.",
    "animals": [], "scenes": [],
}

for animal, face in CHARACTERS:
    mask = Image.new("L", atlas.size)
    queue = deque([face])
    mask.putpixel(face, 255)
    while queue:
        x, y = queue.popleft()
        for point in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            px, py = point
            if 0 <= px < atlas.width and 0 <= py < atlas.height:
                if not mask.getpixel(point) and alpha.getpixel(point) >= 96:
                    mask.putpixel(point, 255)
                    queue.append(point)
    mask = mask.filter(ImageFilter.MaxFilter(9))
    cutout = atlas.copy()
    cutout.putalpha(ImageChops.multiply(alpha, mask))
    bounds = cutout.getbbox()
    body = cutout.crop(bounds)
    canvas = Image.new("RGBA", (352, 400))
    canvas.alpha_composite(body, ((352 - body.width) // 2, 390 - body.height))
    avatar_bounds = (face[0] - 75, face[1] - 75, face[0] + 75, face[1] + 75)
    avatar = cutout.crop(avatar_bounds)
    for suffix, image in (("", canvas), ("-avatar", avatar)):
        folder = CATALOG / f"Companion-{animal}{suffix}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        image.save(folder / "image.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "image.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")
    manifest["animals"].append({
        "id": animal, "source": "originals/atlas.png", "source_bounds": bounds,
        "body_pixels": [352, 400], "avatar_source_bounds": avatar_bounds,
        "avatar_pixels": [150, 150], "transparent": True,
        "surfaces": ["personal hero", "duel preview", "stock picker", "preview avatar"],
    })

for scene in ("race", "tennis"):
    folder = CATALOG / f"Companion-{scene}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for theme in ("Day", "Night"):
        original = SOURCE / f"originals/{scene}{theme}.png"
        image = Image.open(original)
        (folder / f"{theme.lower()}.png").write_bytes(original.read_bytes())
        entry = {"filename": f"{theme.lower()}.png", "idiom": "universal"}
        if theme == "Night":
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
        manifest["scenes"].append({
            "id": f"{scene}-{theme.lower()}", "source": f"originals/{scene}{theme}.png",
            "pixels": list(image.size), "transparent": False, "crop": "none; aspect fit",
            "surfaces": ["demo fight" if scene == "race" else "artwork preview only; never a Feed post"],
        })
    (folder / "Contents.json").write_text(json.dumps({
        "images": images, "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

(SOURCE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Prepared {len(CHARACTERS)} animals and 2 scenes.")
