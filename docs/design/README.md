# Design

**Source of truth:** [`source/`](source/README.md) — the approved web kit (tokens, inventory, screenshots).

**Selected Companion direction:** [`companion-implementation-plan.md`](companion-implementation-plan.md) and [the tappable layout](source/kit/companion-app-proposal.html). The first implementation checkpoint is the native Simulator review; account identity and generation follow acceptance.

**Design options for Marc:** one self-contained HTML page per screen in [`source/kit/`](source/README.md), every option behind a picker, built from the kit tokens. PRs still require Marc’s explicit request. Proposal-only work does not change Swift — see [`AGENTS.md`](../../AGENTS.md).

Rebuild SwiftUI from that folder. Ignore Arena / Pulse / Locker / Rogue; those were placeholders.

- App tokens: `FitFight/DesignSystem/tokens.json` (copy of `source/tokens.json`)
- Theme = **Night / Day**, fixed Moss / Ember / Gold semantics. Switch the base in **You → Look**. There is no accent picker.
- Version stays at the top of You only. Versions lives under You → Settings.
