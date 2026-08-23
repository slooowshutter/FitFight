# FitFight design source

**This folder is the source of truth for how FitFight looks.**

It is a verbatim dump of the web design system we built and approved. Every
colour, size, component and screen in here has been looked at and signed off.
Rebuild it natively in SwiftUI.

> **Ignore the Arena, Pulse, Locker and Rogue names.** Those were placeholders.
> Extra looks in the iOS app (Ink, Paper, Harbor, Grid, Dusk) are optional
> overlays. This folder is still **Classic**. Do not port them into `tokens.json`.

---

## What's here

| File | What it is |
|---|---|
| [`tokens.json`](./tokens.json) | Every design value, machine-readable. Start here. |
| [`tokens.md`](./tokens.md) | The same values as tables, with where each one is used. |
| [`INVENTORY.md`](./INVENTORY.md) | Every screen, every component, every tap and what it does. |
| [`screenshots/INDEX.md`](./screenshots/INDEX.md) | Filename → screen → what was tapped. |
| [`screenshots/app/`](./screenshots/app/) | The product mock. 49 shots, 393×852 pt at @2x. |
| [`screenshots/system/`](./screenshots/system/) | The style guide. 27 shots. |

---

## How to read `tokens.json`

A theme is **one base × one accent**, flattened into a single object:

```
theme  =  BASES[base]      +  ACCENTS[accent]  +  DATA
          bg, surface,        accent,             green, blue,
          surface2, line,     accentDim,          amber, red
          hair, text,         ink
          muted, faint,
          scrim, chip, track
          (11)                (3)                 (4)      = 21 fields
```

- `colors.resolvedDefault` — the default theme (dark + blue) already flattened.
  If you want one concrete set to start from, use this.
- `colors.bases` — the two neutral halves. Two values for every field.
- `colors.accents` — the ten accents. **Pick one per install.** There is no
  second brand colour.
- `colors.data` — green/blue/amber/red. These carry meaning (money up, money
  down, warning) so they are **fixed across every accent**. Never swap them for
  the accent.
- `colors.tints` — a tint is the accent at a fixed alpha, not a separate hex.

Everything else (`type`, `space`, `radius`, `stroke`, `shadow`, `motion`,
`opacity`, `zIndex`, `icons`, `avatar`) is plain numbers in points.

### The shape this should take in SwiftUI

One `Theme` struct with those 21 colour fields, one instance in the environment,
and views that read `theme.surface` instead of writing `Color(...)`. That is the
whole architecture. If a view hard-codes a colour, it is wrong.

`scrim` is an `r,g,b` triple, not a hex — it gets an alpha applied at use.

---

## The app, tab by tab

Four tabs, no raised centre button, fixed order.

### 1 · Fights — the list
[`001-fights-list-top.png`](./screenshots/app/001-fights-list-top.png) ·
[`002-fights-list-bottom.png`](./screenshots/app/002-fights-list-bottom.png)

Every fight is a **card that already carries its own leaderboard and its own
money line**, so the list answers "am I winning?" and "am I up or down?" without
a tap. That is the whole idea of the design — do not replace the cards with
plain rows.

Three groups, in order: live fights (full cards) → Invitations (compact rows) →
Finished (compact rows, dimmed).

### 2 · Fight detail — pushed from the list
[`003`](./screenshots/app/003-fight-winner-takes-all-top.png) ·
[`004`](./screenshots/app/004-fight-winner-takes-all-bottom.png) ·
[`006`](./screenshots/app/006-fight-proportional-top.png) ·
[`009`](./screenshots/app/009-fight-hit-your-goal-top.png) ·
[`012` not joined](./screenshots/app/012-fight-invited-not-joined.png) ·
[`013` finished](./screenshots/app/013-fight-finished.png)

Nav bar → hero (ring + three stat tiles) → **Money right now** → Standings →
Every day so far → share.

"Money right now" is the piece that matters most: for each player, where they
land in dollars **if everyone holds their current pace**. Three settlement modes
(winner takes all / proportional / hit your goal) change the maths and the copy,
never the layout.

### 3 · New — create a fight
[`014`](./screenshots/app/014-new-top.png) …
[`027`](./screenshots/app/027-new-mode-goal-summary.png)

Metric → who's in → when it ends (presets or a real date) → what's on the line →
how it settles → (goal only) daily goal → summary sentence → Start fight.

Two things to get right:
- **Length uses the native date picker.** Presets fill it in; the day count
  updates live. Never build a custom calendar.
- **Proportional disappears when the stake is an action.** A favour can't be cut
  into percentages.

### 4 · Requests — the roadmap
[`028`](./screenshots/app/028-requests-top.png) ·
[`030` voted](./screenshots/app/030-requests-voted.png) ·
[`031`](./screenshots/app/031-requests-filter-features.png)

Features and bugs from everyone, ranked by votes. Filter Top / Features / Bugs.
Tapping the upvote fills it with the accent and increments the count.

### 5 · You — profile
[`033`](./screenshots/app/033-you-top.png) ·
[`034`](./screenshots/app/034-you-bottom.png)

Record, fight history, connected data sources, settings.

### Light mode and accents
[`035`–`039`](./screenshots/app/035-light-fights-list.png) are the same screens
on the light base. [`040`–`049`](./screenshots/app/040-accent-red.png) are the
Fights list in each of the ten accents. Both bases are first-class; pick the
accent once.

---

## Non-negotiables

Pulled from the style guide. These are the rules that make it look like one app:

1. **Accent means "yours" or "first place".** Never decoration.
2. **Money is green up, red down, faint when even.** Never the accent.
3. **Every number is tabular** so columns don't jitter as they tick.
4. **Rows are separated by a 1px hairline**, not by a gap.
5. **A screen answers its question above the fold**; scrolling is for detail.
6. **One primary button per screen**, at the bottom, full width, pill.
7. **One progress ring per screen**, at most.
8. **Loading shows the shape of what's coming**, not a spinner.
9. **Destructive actions are red**, confirmed once, never the default.
10. **A new screen starts at the top.** Scroll position never carries over.

Copy rules, accessibility floors and the full component catalogue are in
[`INVENTORY.md`](./INVENTORY.md) and the `system/` screenshots.

---

## What NOT to copy

**None of the web implementation.** There is no React, Next.js, Tailwind,
shadcn or CSS in this folder, and none should end up in the iOS app.

- Do not port component code. Port the **look and the behaviour**.
- Do not add a web view, a JS bridge, or a CSS-in-Swift layer.
- Do not copy Tailwind class names into Swift constants. Use `tokens.json`.
- Do not recreate the theme/accent switcher bar from `/` — that is a design
  tool that sat outside the phone, not a product feature. The accent is a
  build-time or settings choice.
- Do not copy the phone frame, the fake status bar, or the Dynamic Island
  cut-out. Those are the mock's chrome; iOS gives you the real thing.
- Do not port the demo content (Maya, Leo, Sam, "FIGHT-742"). It is fixture
  data for the mock.
- Do not use Manrope. Ship the system font — SF Pro. Manrope was the web
  stand-in; match the **scale and weights** in `tokens.json`, not the typeface.
- Icons map to **SF Symbols**. Match the weight, not the exact path.

---

## Gaps

These were never designed. Don't invent them — ask:

notifications · request compose and threads · profile edit · settings
sub-screens · payouts · sign-in and onboarding · HealthKit permission prompts ·
per-person goals in the create flow · the settle-up flow at the end of a fight.

---

## Provenance

Generated from the web design system at
`marclelamy/fitfight-v2`, path `app-design-demo/`. Exact commit, branch and
generation notes are in `tokens.json` → `meta`. Screenshots were captured with
Playwright against the running app; the product shots are clipped to the phone
screen element so each PNG is exactly one device screen with no browser chrome.
