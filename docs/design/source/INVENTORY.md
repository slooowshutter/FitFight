# Inventory

Everything in the web design system and the product mock: screens, components,
and every tap with what it does.

Screenshots referenced here live in [`screenshots/`](./screenshots/) — see
[`screenshots/INDEX.md`](./screenshots/INDEX.md) for the full list.

---

## 1. Routes

The web source has exactly two routes. Both are tools, not product surfaces —
the product is what renders **inside the phone frame** on `/`.

| Route | What it is | Ports to iOS? |
|---|---|---|
| `/` | The product mock inside a phone frame, plus a theme/accent switcher above it | The **phone contents** port. The switcher is a design tool — it becomes a build-time or settings choice, not a floating bar. |
| `/system` | The style guide: tokens, components, rules | Does not port. It is the specification. |

There is no router inside the product. The app is one screen with a tab index
and an optional open fight id — mirror that with `@State` / `NavigationStack`.

---

## 2. Product structure

Four tabs, no raised centre button. Order is fixed.

| # | Tab | Icon | Screen |
|---|---|---|---|
| 1 | Fights | `sword` | Fight list |
| 2 | New | `plus` | Create a fight |
| 3 | Requests | `chat` | Feature requests and bugs |
| 4 | You | `user` | Profile |

**Fight detail** is pushed from Fights. It keeps the tab bar visible. Switching
tabs clears it.

> **Every screen starts at the top.** Scroll position never carries over between
> screens — this was a real bug in the web build; do not reproduce it.

---

## 3. Screens, and every tap on them

### 3.1 Fights — the list
`001-fights-list-top.png`, `002-fights-list-bottom.png`

| Element | Tap does |
|---|---|
| Header count "3 live fights" | Nothing — it is a label |
| Header money line "If it ends like this you're −$2" | Nothing — sum of your projected net across live fights |
| Bell button, top right | Notifications (not designed yet). Red dot = unread |
| **Live fight card** ×3 | Pushes the fight detail for that fight |
| Card rank badge (`#2 of 3`) | Not separately tappable — part of the card |
| Card mini-leaderboard rows | Not separately tappable — part of the card |
| Card `N pending` badge | Not tappable. Amber. Shown when someone hasn't accepted |
| Card verdict strip (`−$10 right now`) | Not separately tappable — part of the card |
| **Invitation row** ×2 | Pushes the fight detail, which shows Accept / Join instead of a rank |
| Invitation `Accept` / `Join` button | Accepts in place. In the mock it pushes detail |
| **Finished row** ×1 | Pushes the fight detail in its ended state |

The list has three groups in this order: live fights (full cards), Invitations
(compact rows), Finished (compact rows, 85% opacity).

### 3.2 Fight detail
`003`/`004` winner-takes-all · `006`/`007` proportional · `009`/`010` hit-your-goal · `012` not joined · `013` finished

Top to bottom: nav bar → hero card → Money right now → Standings → Every day so far → share button.

| Element | Tap does |
|---|---|
| `‹ Fights` pill, top left | Pops back to the list, at the top |
| Fight code, centre | Nothing — it is a label |
| Share icon, top right | Opens the share sheet |
| Hero ring | Nothing. Fill is score ÷ leader, or score ÷ your goal in goal mode |
| Three stat tiles | Nothing. Your total · Today · Standing to (money) |
| `Join fight` / `Accept challenge` | Only when you haven't joined. Joins the fight |
| Money right now rows | Nothing. One row per player: projected finish and net dollars |
| `SAFE` / `AT RISK` badge | Goal mode only. Not tappable |
| Standings rows | Nothing. Your row is tinted with the accent |
| `INVITED` row | Someone who hasn't accepted. Greyed avatar, amber badge |
| Day-by-day block | Nothing |
| `i challenge you` button | Opens the share sheet |

Three settlement modes change the copy and the money maths, not the layout:

| Mode | Payout line | Money column |
|---|---|---|
| `winner` | "Winner takes the whole $30" | Leader `+$20`, everyone else `−$10` |
| `proportional` | "Your share of the min is your share of the pot — 60% pays $30" | Share of projected effort minus buy-in |
| `goal` | "Hit 10.0k steps/day and your $20 comes back" | On-pace players split the forfeits; the rest lose their buy-in |

### 3.3 New fight
`014`–`027`

| Element | Tap does |
|---|---|
| **Metric** ×3 radio rows | Selects the metric. Also resets the default daily goal |
| **Who's in** ×5 checkbox rows | Toggles a player. Header count updates |
| **Length** `3d` `7d` `14d` | Sets the end date that many days out |
| **Length** `Pick a date` | Reveals a native date field. Minimum is tomorrow. Day count updates live |
| Date field | Opens the OS date picker. Never build a custom calendar |
| **What's on the line** `Bragging rights` | No stake. Hides the settlement section entirely |
| **What's on the line** `$10` | The default money stake |
| **What's on the line** `Custom` | Reveals a `Money` / `Action` segmented control |
| Custom → `Money` | Reveals a stepper, ±$5 |
| Stepper `−` / `+` | Changes the amount. Minimum $5 |
| Custom → `Action` | Reveals a free-text forfeit field plus three suggestion chips |
| Forfeit text field | Free text: "what does the loser owe?" |
| Forfeit chip ×3 | Fills the field with that suggestion |
| **Settlement** `Winner takes all` | Radio |
| **Settlement** `Proportional` | Radio. **Hidden when the stake is an action** — a favour can't be split by percentage |
| **Settlement** `Hit your goal` | Radio. Reveals the daily goal stepper |
| Goal stepper `−` / `+` | Changes the shared daily target. Step size depends on the metric |
| Summary block | Nothing. Restates every choice in one sentence |
| `Start fight` | Creates the fight |

### 3.4 Requests
`028`–`032`

| Element | Tap does |
|---|---|
| `+ New` button, top right | Opens the compose form (not designed yet) |
| **Talk to the boss** | Opens a private chat with Marc. Sending emails him at marc@marclamy.com. He replies from his inbox. |
| Segment `Top` / `Features` / `Bugs` | Filters and re-sorts the list |
| **Upvote button** on each row | Toggles your vote. Count changes, button fills with the accent |
| Row body | Opens the request thread (not designed yet) |
| `feature` / `bug` badge | Not tappable |
| `Open` / `Planned` / `Shipped` status | Not tappable |
| Comment count | Opens the thread |

### 3.5 You
`033`, `034`

| Element | Tap does |
|---|---|
| `Edit` button | Edits the profile |
| Four stat tiles | Nothing |
| Fight history rows | Opens that fight |
| Data source rows | Opens the connection settings for that source |
| Settings rows ×4 | Push a settings sub-screen each |

---

## 4. Components

Every one is rendered in `/system` — see `screenshots/system/`.

### Buttons — `057-dark-08-buttons.png`
Primary (accent fill, ink text, full width, pill) · Secondary (chip fill, accent
text) · Quiet (1px border, muted text) · Destructive (red at 12%, red text) ·
Disabled (chip fill, faint text, 60% opacity) · Loading (primary at 75% with a
spinner) · Small pill · Icon button (40pt circle, 1px border) · Destructive icon
button.

**One primary per screen, at the bottom, full width.**

### Chips & segmented — `057`
Selected chip (accent fill) · Unselected (surface + border) · Suggestion (chip
fill, accent text) · Segmented control (chip track, surface thumb with a small
shadow).

### Inputs — `058-dark-09-inputs.png`
Text field in four states: default, focused (accent border + 3px ring at 20%),
error (red border + red hint), disabled (60% opacity). Search field (chip fill,
inline icon). Switch. Radio, filled and empty. Checkbox. Stepper (− value +).
Slider. Date field with a live day count.

### Rows — `059-dark-10-rows.png`
Rows are always grouped inside a card and separated by a 1px hairline, never a
gap. Variants: navigates (chevron) · carries a value · avatar + two lines +
trailing action · destructive (red tint) · swipe-open (red delete panel).

### Leaderboard row — `059`
Rank number · avatar · name · today's delta · total · progress bar underneath.
Your row is tinted with the accent at 7%. Rank 1 takes the accent.
Invited players appear at the bottom, avatar at 50%, amber `INVITED` badge.

### Stat tiles & summary — `059`
2–4 tiles in a row: big tabular value over a 9pt uppercase label, chip fill.
Summary block: chip fill, 12pt, restates the choices right before the primary button.

### Data — `060-dark-11-data.png`
Money (`+$14` green / `−$10` red / `even` faint) · delta with an arrow ·
progress bar · sparkline · day bars (winner takes the accent) · progress ring.
Number formats: `61,420 → 61.4k`, minutes stay whole, money rounds to the dollar,
dates `Mon 27 Jul`, times `9:32`, relative `2h ago` / `1d ago` / `1w ago`.

### People — `061-dark-12-people.png`
Avatar sizes 24/32/40/56, accent ring for the viewer, initials fallback when
there's no photo, overlapping stack with a `+N` overflow, eight status badges.

### Feedback — `062-dark-13-feedback.png`
Banner in four tones (info/success/warning/error, tinted background + 20% border
+ icon + dismiss) · toast (raised pill with an Undo) · alert (title, body, two
buttons, destructive on the right) · bottom sheet (grab handle, title, rows) ·
empty state (icon tile, title, sentence, button) · error state · skeleton rows
that match the shape of the row they replace.

### Navigation — `063-dark-14-navigation.png`
Status bar · nav bar (back pill, centre label, trailing icon button) · large
title under the bar · sub-tabs (underline, never pills) · tab bar (icon over a
10pt label, accent when active, 1pt dot above) · section header (13pt bold, with
an optional accent action on the right).

---

## 5. Light and dark

Both exist and are equal citizens. Every base token has a light value; nothing
in the layout changes. Light captures: `035`–`039` (product) and `068`–`075`
(style guide).

Ten accents work against either base — `040`–`049` show the same screen in each.
`ink` is pre-checked for contrast on every accent (only Yellow uses dark ink).

---

## 6. States covered

| State | Where |
|---|---|
| Empty | `062` — "No fights yet" |
| Error | `062` — "Couldn't load your fights" |
| Loading | `062` — skeleton rows |
| Disabled | `057` — disabled button, `058` — disabled field |
| Selected | `058` radios/checkboxes, `031`/`032` segments, `030` voted |
| Focused | `058` — focused text field |
| Pending / invited | `006`, `009` — greyed avatar + amber badge |
| Not joined | `012` — Accept CTA instead of a rank |
| Finished | `013` — ended fight |
| At risk | `010` — goal mode, `AT RISK` badge |

---

## 7. Not designed yet

Honest gaps — do not invent these, ask first:

- Notifications screen (the bell has no destination)
- Request compose form and request thread
- Profile edit, settings sub-screens, payouts
- Sign-in, onboarding, HealthKit permission prompts
- Per-person goals in the create flow (the data model supports them; the UI ships one shared goal)
- Settle-up / payment flow at the end of a fight
