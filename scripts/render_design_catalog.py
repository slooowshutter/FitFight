#!/usr/bin/env python3
"""Render docs/design previews from FitFight/DesignSystem/themes.json.

Source of truth is the JSON. SwiftUI loads the same file from the app bundle.
Re-run after changing tokens:

    python3 scripts/render_design_catalog.py
"""

from __future__ import annotations

import json
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEMES_PATH = ROOT / "FitFight" / "DesignSystem" / "themes.json"
OUT_DIR = ROOT / "docs" / "design"

FONT_STACK = {
    "rounded": '-apple-system, BlinkMacSystemFont, "SF Pro Rounded", "Nunito", sans-serif',
    "default": '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
    "condensed": '"Arial Narrow", "Franklin Gothic Condensed", Impact, sans-serif',
    "serif": 'Georgia, "Iowan Old Style", serif',
    "mono": 'ui-monospace, "SF Mono", Menlo, monospace',
}

WEIGHT = {
    "regular": 400,
    "medium": 500,
    "semibold": 600,
    "bold": 700,
    "heavy": 800,
    "black": 900,
}


def load_themes() -> list[dict]:
    data = json.loads(THEMES_PATH.read_text())
    themes = data["themes"]
    if not themes:
        raise SystemExit("themes.json has no themes")
    return themes


def font_family(role: str) -> str:
    return FONT_STACK.get(role, FONT_STACK["default"])


def svg_for(theme: dict) -> str:
    c = theme["colors"]
    r = theme["radius"]
    t = theme["type"]
    display = font_family(t["display"])
    body = font_family(t["body"])
    mono = font_family(t["mono"])
    weight = WEIGHT.get(t["displayWeight"], 800)
    radius_md = r["md"]
    radius_lg = r["lg"]
    radius_sm = r["sm"]

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 844" width="390" height="844">
  <rect width="390" height="844" rx="40" fill="{c["bg"]}"/>
  <text x="195" y="42" text-anchor="middle" font-family="{escape(mono)}" font-size="12" font-weight="600" fill="{c["muted"]}">0.2.0</text>
  <text x="195" y="130" text-anchor="middle" font-family="{escape(display)}" font-size="{t["displaySize"]}" font-weight="{weight}" fill="{c["text"]}">FitFight</text>
  <text x="195" y="168" text-anchor="middle" font-family="{escape(body)}" font-size="16" fill="{c["muted"]}">Challenge your friends.</text>
  <text x="195" y="190" text-anchor="middle" font-family="{escape(body)}" font-size="16" fill="{c["muted"]}">Winner takes the glory.</text>
  <rect x="28" y="220" width="334" height="52" rx="{radius_md}" fill="{c["accent"]}"/>
  <text x="195" y="252" text-anchor="middle" font-family="{escape(body)}" font-size="17" font-weight="600" fill="{c["accentText"]}">Design</text>
  <rect x="28" y="284" width="334" height="52" rx="{radius_md}" fill="{c["surface"]}" stroke="{c["border"]}"/>
  <text x="195" y="316" text-anchor="middle" font-family="{escape(body)}" font-size="17" font-weight="600" fill="{c["text"]}">Versions</text>
  <rect x="28" y="360" width="334" height="148" rx="{radius_lg}" fill="{c["surface"]}" stroke="{c["border"]}"/>
  <rect x="44" y="380" width="72" height="24" rx="{radius_sm}" fill="{c["accent"]}"/>
  <text x="80" y="397" text-anchor="middle" font-family="{escape(body)}" font-size="12" font-weight="600" fill="{c["accentText"]}">{escape(theme["name"])}</text>
  <rect x="124" y="380" width="70" height="24" rx="{radius_sm}" fill="{c["raised"]}"/>
  <text x="159" y="397" text-anchor="middle" font-family="{escape(body)}" font-size="12" font-weight="600" fill="{c["text"]}">sample</text>
  <text x="44" y="436" font-family="{escape(body)}" font-size="20" font-weight="700" fill="{c["text"]}">5K before Sunday</text>
  <text x="44" y="464" font-family="{escape(body)}" font-size="14" fill="{c["muted"]}">Placeholder card. Real fights come later.</text>
  <rect x="28" y="528" width="106" height="78" rx="{radius_md}" fill="{c["surface"]}" stroke="{c["border"]}"/>
  <text x="44" y="562" font-family="{escape(body)}" font-size="22" font-weight="700" fill="{c["text"]}">12</text>
  <text x="44" y="584" font-family="{escape(body)}" font-size="12" fill="{c["muted"]}">Wins</text>
  <rect x="142" y="528" width="106" height="78" rx="{radius_md}" fill="{c["surface"]}" stroke="{c["border"]}"/>
  <text x="158" y="562" font-family="{escape(body)}" font-size="22" font-weight="700" fill="{c["text"]}">4</text>
  <text x="158" y="584" font-family="{escape(body)}" font-size="12" fill="{c["muted"]}">Streak</text>
  <rect x="256" y="528" width="106" height="78" rx="{radius_md}" fill="{c["surface"]}" stroke="{c["border"]}"/>
  <text x="272" y="562" font-family="{escape(body)}" font-size="22" font-weight="700" fill="{c["text"]}">2</text>
  <text x="272" y="584" font-family="{escape(body)}" font-size="12" fill="{c["muted"]}">Open</text>
  <text x="195" y="800" text-anchor="middle" font-family="{escape(body)}" font-size="14" fill="{c["muted"]}">{escape(theme["blurb"])}</text>
</svg>
"""


def html_catalog(themes: list[dict]) -> str:
    payload = json.dumps(themes)
    cards = []
    for theme in themes:
        cards.append(
            f'<a class="thumb" href="#{escape(theme["id"])}">'
            f'<img src="{escape(theme["id"])}.svg" alt="{escape(theme["name"])}">'
            f'<span>{escape(theme["name"])}</span></a>'
        )
    thumbs = "\n".join(cards)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FitFight design catalog</title>
  <style>
    :root {{ --bg:#0b0b0b; --text:#f4f1ea; --muted:#9a9588; }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: var(--bg);
      color: var(--text);
    }}
    header {{
      position: sticky; top: 0; z-index: 4;
      padding: 14px 16px 12px;
      background: color-mix(in srgb, var(--bg) 88%, black);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid color-mix(in srgb, var(--text) 12%, transparent);
    }}
    h1 {{ margin: 0; font-size: 20px; }}
    .blurb {{ margin: 6px 0 12px; color: var(--muted); font-size: 14px; }}
    .pills {{ display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px; }}
    .pills button {{
      border: 0; border-radius: 999px; padding: 8px 14px;
      font: 600 14px/1 inherit; white-space: nowrap; cursor: pointer;
      background: color-mix(in srgb, var(--text) 10%, transparent);
      color: var(--text);
    }}
    .pills button[aria-selected="true"] {{ background: var(--accent, #e8c547); color: var(--accentText, #111); }}
    main {{ padding: 16px; max-width: 720px; margin: 0 auto; }}
    .phone {{
      width: min(100%, 390px);
      margin: 0 auto 24px;
      border-radius: 40px;
      overflow: hidden;
      box-shadow: 0 24px 80px rgba(0,0,0,.45);
    }}
    .phone img {{ display: block; width: 100%; height: auto; }}
    .swatches {{ display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin-bottom: 24px; }}
    .swatch {{ border-radius: 10px; min-height: 52px; border: 1px solid rgb(255 255 255 / .08); }}
    .swatch span {{ display:block; font-size: 11px; padding: 6px; color: var(--muted); }}
    .thumbs {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }}
    .thumb {{ color: inherit; text-decoration: none; }}
    .thumb img {{ width: 100%; border-radius: 24px; }}
    .thumb span {{ display:block; text-align:center; margin-top: 8px; font-weight: 600; }}
  </style>
</head>
<body>
  <header>
    <h1>FitFight design</h1>
    <p class="blurb" id="blurb">Tap a theme. Same tokens as the iOS app.</p>
    <div class="pills" id="pills"></div>
  </header>
  <main>
    <div class="phone"><img id="hero" alt="Theme preview"></div>
    <div class="swatches" id="swatches"></div>
    <div class="thumbs">
      {thumbs}
    </div>
  </main>
  <script>
    const themes = {payload};
    const pills = document.getElementById("pills");
    const hero = document.getElementById("hero");
    const blurb = document.getElementById("blurb");
    const swatches = document.getElementById("swatches");

    function apply(id) {{
      const theme = themes.find(t => t.id === id) || themes[0];
      document.documentElement.style.setProperty("--bg", theme.colors.bg);
      document.documentElement.style.setProperty("--text", theme.colors.text);
      document.documentElement.style.setProperty("--muted", theme.colors.muted);
      document.documentElement.style.setProperty("--accent", theme.colors.accent);
      document.documentElement.style.setProperty("--accentText", theme.colors.accentText);
      blurb.textContent = theme.blurb;
      hero.src = theme.id + ".svg";
      hero.alt = theme.name + " preview";
      for (const button of pills.querySelectorAll("button")) {{
        button.setAttribute("aria-selected", button.dataset.id === theme.id ? "true" : "false");
      }}
      const keys = ["bg","surface","raised","text","muted","accent","accentText","danger","dangerText","success","border"];
      swatches.innerHTML = keys.map(k =>
        `<div class="swatch" style="background:${{theme.colors[k]}}"><span>${{k}}</span></div>`
      ).join("");
      history.replaceState(null, "", "#" + theme.id);
    }}

    for (const theme of themes) {{
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.id = theme.id;
      button.textContent = theme.name;
      button.addEventListener("click", () => apply(theme.id));
      pills.appendChild(button);
    }}

    const initial = location.hash.replace("#", "") || themes[0].id;
    apply(initial);
  </script>
</body>
</html>
"""


def readme(themes: list[dict]) -> str:
    sections = []
    for theme in themes:
        sections.append(
            f"## {theme['name']}\n\n"
            f"{theme['blurb']}\n\n"
            f"![{theme['name']}]({theme['id']}.svg)\n"
        )
    body = "\n".join(sections)
    return f"""# Design catalog

This is the SwiftUI equivalent of a shadcn kit: tokens, then components, then screens.

**Do not wait on TestFlight to pick a look.** The previews below render on GitHub (including the phone app). `catalog.html` is interactive, but GitHub’s file viewer won’t run it — use [htmlpreview](https://htmlpreview.github.io/) with this file’s GitHub URL if you want the switcher.

Source of truth: [`FitFight/DesignSystem/themes.json`](../../FitFight/DesignSystem/themes.json). After you change it:

```
python3 scripts/render_design_catalog.py
```

The iOS app loads that same JSON. Home + **Design** in the app stay in sync with these previews.

{body}
Version stays at the top of the screen in every theme.
"""


def main() -> None:
    themes = load_themes()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for theme in themes:
        (OUT_DIR / f"{theme['id']}.svg").write_text(svg_for(theme))
    (OUT_DIR / "catalog.html").write_text(html_catalog(themes))
    (OUT_DIR / "README.md").write_text(readme(themes))
    print(f"Wrote {len(themes)} theme previews to {OUT_DIR}")


if __name__ == "__main__":
    main()
