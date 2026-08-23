# Design

**Source of truth:** [`source/`](source/README.md) — the approved web kit (tokens, inventory, screenshots).

Rebuild SwiftUI from that folder. Ignore Arena / Pulse / Locker / Rogue; those were placeholders.

- App tokens: `FitFight/DesignSystem/tokens.json` (copy of `source/tokens.json`)
- Theme = **look** × base × accent. Default look is **Classic** (the approved kit in `tokens.json`). Five more looks live in **You → Look** and **Settings → Design**. Don't put those palettes into `tokens.json`.
- Version stays at the top of the screen. Versions lives under You → Settings.
