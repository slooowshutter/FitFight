# FitFight design source

This folder contains the current approved design and the archived design dump it replaced.

## Current source of truth

| File                                                                             | Purpose                                                                                                                  |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| [`kit/FitFight Design System.dc.html`](./kit/FitFight%20Design%20System.dc.html) | Approved visual specification and interactive component catalogue.                                                       |
| [`kit/support.js`](./kit/support.js)                                             | Runtime used by the HTML source. Documentation only; it is not bundled in the iOS app.                                   |
| [`tokens.json`](./tokens.json)                                                   | Machine-readable SwiftUI tokens. This must remain byte-for-byte identical to `FitFight/DesignSystem/tokens.json`.        |
| [`kit/companion-app-proposal.html`](./kit/companion-app-proposal.html)           | Selected Companion screen direction, retained as the tappable reference. Existing native behavior remains authoritative. |
| [`kit/you-tab-proposals.html`](./kit/you-tab-proposals.html) | Twenty Companion-based You tab proposals: ten close refinements and ten creative explorations, plus original #5 for comparison. Shared stats, Night/Day, and editing through Settings. |
| [`kit/you-tab-rethink-proposals.html`](./kit/you-tab-rethink-proposals.html) | Fifteen You tab designs on one draggable picker. Round 1 answers what the page is for: Summit (companion poses as your form, recommended), Scorecard, This week, Fighter card and Quiet. Round 2 adds Ridge, Logbook, Next fight, Journal, Poster, Bento, Stories, Profile grid, Walk and fight, and Coach. Round 3 adds Rings, Heatmap, and two multi-sport layouts (Sport lanes, and Sport list with a stats card and Day, Week, Month breakdown; Bike and Swim are sample), Live first, Trophy shelf, Stat strip and One number. Ten Friends designs list people by total shared fights. Dashboard has Steps, Streaks, Fights and Sports tabs, Month vs month, Badges, Records and a Your own metric idea. The picker's Drawer set holds Marc's shortlist: Current, Duel stage, Tale of the tape and five mixes of them. The You picker holds his shortlist: Sport list, Sport lanes, Stat strip and Heatmap. Chart kit catalogues 25 dashboard chart types, dashboard rules and a proposed extended palette. Same sample data, Night/Day. Proposals only. |
| [`companion/`](./companion/README.md)                                            | Preserved artwork, asset manifest, reproducible crops, and native review captures.                                       |

The [private You tab preview](https://fitfight-five-designs.marc719509.chatgpt.site/you-tab-proposals.html)
compares twenty new layouts based on Marc's selected fifth design, Companion.
Close and Creative each contain ten options; Original #5 keeps the selected
reference one tap away. Every option uses the same sample data. These are proposals,
not an approved spec or a native app update. Edits stay in the preview session.

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

- Four fixed tabs: Fights, New, You, Feedback.
- The version label stays at the top of You only. Do not show it on Fights, New, Feed, or Feedback.
- Versions remains permanently available under You → Settings.
- Every number uses tabular figures.
- Rows use hairline dividers; selected fills use concentric corners and hide adjacent dividers without shifting layout.
- One primary full-width pill button per screen.
- Destructive actions use Ember and require confirmation.
- Loading shows the shape of upcoming content.
- A newly opened screen starts at the top.

Night is the primary authored mode. The HTML supplies nine Day swatches; semantic Day values that the source does not draw are derived in `tokens.json` and documented in its `meta` block.
