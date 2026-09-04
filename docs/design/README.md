# Design

**Source of truth:** [`source/`](source/README.md) — the approved web kit (tokens, inventory, screenshots).

**Design options for Marc:** one self-contained HTML page per screen in [`source/kit/`](source/README.md), every option behind a picker in the same page, built from the kit tokens. Push it and reply with an `htmlpreview.github.io` link so he taps it on his phone. Never AI-generated images, and never a `.swift` change in that PR — see [`AGENTS.md`](../../AGENTS.md).

Rebuild SwiftUI from that folder. Ignore Arena / Pulse / Locker / Rogue; those were placeholders.

- App tokens: `FitFight/DesignSystem/tokens.json` (copy of `source/tokens.json`)
- Theme = one **base** (dark/light) × one **accent** (10 colours). Pick the accent in **You → Look**.
- Version stays at the top of the screen. Versions lives under You → Settings.
