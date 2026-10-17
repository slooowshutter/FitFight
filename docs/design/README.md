# Design

**Source of truth:** [`source/`](source/README.md) — the approved web kit (tokens, inventory, screenshots).

**Selected Companion direction:** [`companion-implementation-plan.md`](companion-implementation-plan.md) and [the tappable layout](source/kit/companion-app-proposal.html). The first implementation checkpoint is the native Simulator review; account identity and generation follow acceptance.

**The app mirror:** [`source/kit/app.html`](source/kit/app.html) is the whole app in one tappable page with fake data. Design options are built on it, behind its In progress picker, and every native UI change updates it. See [app-mirror.md](app-mirror.md). PRs still require Marc’s explicit request. Proposal-only work does not change Swift; see [`AGENTS.md`](../../AGENTS.md).

Rebuild SwiftUI from that folder. Ignore Arena / Pulse / Locker / Rogue; those were placeholders.

- App tokens: `FitFight/DesignSystem/tokens.json` (copy of `source/tokens.json`)
- Theme = **Night / Day**, fixed Moss / Ember / Gold semantics. Switch the base in **You → Look**. There is no accent picker.
- Version stays at the top of Profile only. Versions lives under Profile → Settings.
