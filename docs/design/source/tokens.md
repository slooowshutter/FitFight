# Tokens

Same values as [`tokens.json`](./tokens.json), in a form you can read. Generated from it — if the two ever disagree, the JSON wins.

Source: `https://github.com/marclelamy/fitfight-v2` @ `d02bcef78662` (branch `fitfight-design-system`, path `app-design-demo/`).

---

## How a theme resolves

A theme is **one base** × **one accent**, flattened into a single object. Every surface in the app reads a field off that object. Nothing hard-codes a colour.

```
theme = BASES[base] + ACCENTS[accent] + DATA
       (11 fields)   (3 fields)        (4 fields)   = 21 fields
```

In SwiftUI: one `Theme` struct, one instance in `@Environment`, and views read `theme.surface` rather than `Color(...)`.

## Colour — bases

The neutral half of the theme. Two bases, eleven fields each.

| Token | Dark | Light | Where it's used |
|---|---|---|---|
| `bg` | `#101114` | `#f4f4f6` | Screen background, behind everything |
| `surface` | `#191b1f` | `#ffffff` | Cards, grouped lists, the tab bar |
| `surface2` | `#212429` | `#eaeaee` | Raised things — toasts, sheets, alerts |
| `line` | `rgba(255,255,255,0.10)` | `rgba(0,0,0,0.10)` | 1px border on a card or input |
| `hair` | `rgba(255,255,255,0.06)` | `rgba(0,0,0,0.065)` | 1px divider between rows inside a card |
| `text` | `#ffffff` | `#15171a` | Primary text, big numbers |
| `muted` | `rgba(255,255,255,0.62)` | `rgba(0,0,0,0.58)` | Sentences, secondary values |
| `faint` | `rgba(255,255,255,0.40)` | `rgba(0,0,0,0.42)` | Labels, handles, timestamps, empty dashes |
| `scrim` | `16,17,20` | `21,23,26` | `r,g,b` triple for the photo/modal scrim |
| `chip` | `rgba(255,255,255,0.055)` | `rgba(0,0,0,0.045)` | Inset fill — chips, stat tiles, icon squares |
| `track` | `rgba(255,255,255,0.09)` | `rgba(0,0,0,0.08)` | Unfilled part of a progress bar or ring |

## Colour — accents

Ten. **One is chosen per install**; there is no second brand colour. `accent` is the fill, `accentDim` is the darker end of the ring gradient, `ink` is the text colour that sits on top of the accent.

| Name | accent | accentDim | ink |
|---|---|---|---|
| `red` — Red | `#e11d1d` | `#a51414` | `#ffffff` |
| `orange` — Orange | `#f2700a` | `#bb4f00` | `#ffffff` |
| `yellow` — Yellow | `#f0ad00` | `#b87f00` | `#17181c` |
| `green` — Green | `#16a34a` | `#0d7a37` | `#ffffff` |
| `teal` — Teal | `#0d9488` | `#086b62` | `#ffffff` |
| `blue` — Blue | `#1a6ef5` | `#114db3` | `#ffffff` |
| `indigo` — Indigo | `#4f46e5` | `#3730b3` | `#ffffff` |
| `purple` — Purple | `#7c3aed` | `#5b21b6` | `#ffffff` |
| `pink` — Pink | `#e0348a` | `#ab2168` | `#ffffff` |
| `graphite` — Graphite | `#3a4048` | `#23272d` | `#ffffff` |

Accent means **“yours”** or **“first place”**. Never decoration.

## Colour — data semantics

Fixed across every accent. These carry meaning, so they never change with the brand colour.

| Token | Value | Where it's used |
|---|---|---|
| `green` | `#16a34a` | Money up, today's gain, on-track badge |
| `blue` | `#2f86e0` | Informational banner, ride activity |
| `amber` | `#e0a010` | Warning, at-risk badge, invited badge, urgency |
| `red` | `#e0483f` | Money down, destructive action, bug label, error |
| `onPhoto` | `#ffffff` | Text over photography — always white |

## Colour — tints

A tint is the accent (or a data colour) at a fixed alpha. Never a separate hex.

| Token | Alpha | Where it's used |
|---|---|---|
| `selectedRow` | `12` (7%) | accent behind the viewer's own row |
| `selectedOption` | `14` (8%) | accent behind a chosen radio row |
| `badge` | `1e` (12%) | any status badge background |
| `focusRing` | `33` (20%) | 3px ring on a focused input |

## Type

Family: `Manrope, ui-sans-serif, system-ui, sans-serif`. Mono: `JetBrains Mono, ui-monospace, SFMono-Regular, monospace`.

**On iOS:** SF Pro Text / SF Pro Display. Manrope is the web stand-in; ship system font on iOS.

Numerals are **tabular in every context — scores, money, ranks, dates**.

| Role | Size | Weight | Tracking | Where it's used |
|---|---|---|---|---|
| `heroNumber` | 34 | 700 | — | the single number a screen is about |
| `display` | 26 | 700 | -0.02em | screen title — '3 live fights' |
| `title` | 23 | 700 | -0.02em | fight name on a card |
| `headline` | 19 | 700 | — | big numbers, rank badge |
| `rank` | 17 | 700 | — | stat tile value |
| `bodyStrong` | 15 | 600 | — | player name, row value |
| `body` | 14 | 400 | — | sentences, blurbs |
| `label` | 13 | 700 | — | section header |
| `caption` | 12 | 400 | — | meta line under a title |
| `micro` | 11 | 400 | — | handles, timestamps |
| `eyebrow` | 10 | 600 | 0.16em | above a title |
| `tiny` | 9 | 600 | — | stat tile label |

### Line heights

| Token | Value | Where it's used |
|---|---|---|
| `none` | 1 | Big numbers that must not add space |
| `tight` | 1.15 | Titles, display |
| `snug` | 1.35 | Two-line blurbs in a row |
| `normal` | 1.5 | Body copy |
| `relaxed` | 1.6 | Summary blocks, longer explanations |

## Spacing

Everything sits on a **4px grid**.

| Token | Value |
|---|---|
| `10` | 10 |
| `14` | 14 |
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `base` | 16 |
| `lg` | 20 |
| `xl` | 28 |

### Layout rules

| Rule | Value |
|---|---|
| `screenPadding` | 16 |
| `cardPadding` | 20 |
| `rowPaddingX` | 16 |
| `rowPaddingY` | 14 |
| `sectionGap` | 28 |
| `cardGap` | 14 |
| `tabBarClearance` | 128 |
| `tabBarPaddingBottom` | 20 |

> Rows are separated by a 1px hairline, never a gap.

## Radius

| Token | Value | Where it's used |
|---|---|---|
| `full` | 9999 | buttons, pills, badges, avatars |
| `xl` | 24 | cards and grouped lists |
| `lg` | 16 | chips, stat tiles, inputs |
| `md` | 12 | segmented-control thumb, icon squares |
| `sm` | 8 | small square markers |
| `device` | undefined | phone frame only — not a product token |

## Stroke

| Token | Value | Where it's used |
|---|---|---|
| `thin` | 1px | Every border in the app |
| `border` (`line`) | dark `rgba(255,255,255,0.10)` · light `rgba(0,0,0,0.10)` | Card and input outline |
| `hairline` (`hair`) | dark `rgba(255,255,255,0.06)` · light `rgba(0,0,0,0.065)` | between rows inside a card |
| `focusRing` | 3px, accent at 20% | Focused text input |
| `selectedUnderline` | 2px, accent | sub-tabs |
| `avatarRing` | 2px + 1.5px gap, accent | marks the viewer |

## Shadow

Nearly flat. Separation comes from surface colour, not shadow.

| Token | Value | Where it's used |
|---|---|---|
| `flat` | `none` | cards, rows — separation comes from surface, not shadow |
| `raised` | `0 10px 15px -3px rgba(0,0,0,0.3), 0 4px 6px -4px rgba(0,0,0,0.3)` | toasts, popovers |
| `modal` | `0 25px 50px -12px rgba(0,0,0,0.5)` | sheets, alerts |
| `segmentThumb` | `0 1px 4px rgba(0,0,0,0.25)` | selected segment |
| `blurBar` | `bg at 90% + blur(20px)` | tab bar, sticky headers |
| `scrim` | `rgba(scrim,0.6)` | behind a modal |

## Motion

| Token | Duration | Easing | Where it's used |
|---|---|---|---|
| `tap` | 120ms | ease-out | press scale to 0.97, colour change |
| `screen` | 220ms | cubic-bezier(0.16, 1, 0.3, 1) | fade + 10px rise between screens |
| `sheet` | 300ms | cubic-bezier(0.16, 1, 0.3, 1) | bottom sheet in and out |
| `spring` | spring | stiffness 500, damping 34 | tab indicator, anything that snaps |

Press feedback: scale to **0.97** for controls, **0.985** for whole cards.

> All durations collapse to 0. Opacity still changes; nothing moves.

## Opacity

| Token | Value | Where it's used |
|---|---|---|
| `disabled` | 0.6 | A disabled control |
| `pendingAvatar` | 0.5 | Avatar of someone who hasn't accepted |
| `finishedCard` | 0.85 | A finished fight in the list |
| `blurBar` | 0.9 | Tab bar / sticky header background |
| `scrim` | 0.6 | Behind a modal |
| `photoNoise` | 0.12 | Grain overlay on photography |

## Z-index

| Token | Value |
|---|---|
| `content` | 0 |
| `stickyHeader` | 30 |
| `tabBar` | 40 |
| `modal` | 50 |
| `dynamicIsland` | 60 |

## Icons

Drawn on a **24×24** grid, 1.8 stroke (1.7 for light detail, 2.4 for a plus or a tick), round caps and joins. currentColor via stroke — icons never carry their own colour

| Context | Size |
|---|---|
| `tabBar` | 22 |
| `button` | 16 |
| `nav` | 15 |
| `inline` | 13 |
| `hint` | 11 |

**The set (27):** `home`, `sword`, `chart`, `user`, `plus`, `bell`, `flame`, `arrow`, `share`, `check`, `crown`, `back`, `chevron`, `users`, `clock`, `coin`, `search`, `chat`, `x`, `trash`, `gear`, `info`, `warn`, `calendar`, `refresh`, `dots`, `link`

On iOS these all map to SF Symbols. Match the weight, not the exact path.

## Avatars

Sizes in use: 18, 20, 22, 24, 26, 30, 32, 34, 36, 38, 40, 56. Stacks overlap by **-32%** of the avatar size. overlap is -32% of the avatar size

## Canvas

| Token | Value |
|---|---|
| Design canvas | 393 × 852 pt — iPhone 15/16 portrait logical points — the design canvas |
| Screenshot viewport | 390 × 844 @2x |
| Dynamic Island | 116 × 34, 12 from the top |
| Safe area bottom | 20 |

The product is single-column at every size. The web breakpoints in `tokens.json` only affect the gallery chrome around the phone and have no iOS meaning.
