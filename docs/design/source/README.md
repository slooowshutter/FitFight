# FitFight design source

This folder contains the current approved design and the archived design dump it replaced.

## Current source of truth

| File | Purpose |
| --- | --- |
| [`kit/FitFight Design System.dc.html`](./kit/FitFight%20Design%20System.dc.html) | Approved visual specification and interactive component catalogue. |
| [`kit/support.js`](./kit/support.js) | Runtime used by the HTML source. Documentation only; it is not bundled in the iOS app. |
| [`kit/fights-home-proposals.html`](./kit/fights-home-proposals.html) | Unshipped Fights home layout options. Kit tokens and components only. Not the approved spec. Not TestFlight. |
| [`kit/fights-row-variants.html`](./kit/fights-row-variants.html) | Twenty variants of the Fights row, titled by the loser action. Proposal only. |
| [`tokens.json`](./tokens.json) | Machine-readable SwiftUI tokens. This must remain byte-for-byte identical to `FitFight/DesignSystem/tokens.json`. |

The approved system has two bases, Night and Day, and fixed semantic colour families:

- Ink: surfaces and text
- Moss: the current User, live state, and winning
- Ember: urgency, destructive actions, and losing
- Gold: progress only

There is no accent picker. Nunito 500/600/700/800 is the approved typeface because that is what the HTML source loads and specifies. Icons use SF Symbols.

The native implementation lives in `FitFight/DesignSystem/`. Port the HTML’s look and behaviour into SwiftUI; never ship a web view, JavaScript bridge, or CSS-in-Swift layer. All colours—including literal white/black overlays from the source—must be named in `tokens.json` before Swift code uses them.

## Archived source

The following files document the previous SF Pro, dark/light × 10-accent direction. They are retained for historical context only and must not guide new implementation:

- `tokens.md`
- `INVENTORY.md`
- `screenshots/`
- `source-app/`

When archived material conflicts with the current HTML or `tokens.json`, the current files win.

## Native rules

- Four fixed tabs: Fights, New, Requests, You.
- The version label stays at the top of the screen.
- Versions remains permanently available under You → Settings.
- Every number uses tabular figures.
- Rows use hairline dividers; selected fills use concentric corners and hide adjacent dividers without shifting layout.
- One primary full-width pill button per screen.
- Destructive actions use Ember and require confirmation.
- Loading shows the shape of upcoming content.
- A newly opened screen starts at the top.

Night is the primary authored mode. The HTML supplies nine Day swatches; semantic Day values that the source does not draw are derived in `tokens.json` and documented in its `meta` block.
