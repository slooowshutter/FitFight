# The app mirror

[`source/kit/app.html`](source/kit/app.html) is the whole FitFight iOS app in one HTML page, with fake data. Every tab,
pushed screen, sheet, drawer, alert, confirmation dialog, menu and empty or error state is there, and every button
does what the app does. The phone is on the left. The map on the right holds the look (Night or Day, Player or Admin,
account state, fake data set) and a link to every screen and dialog. On an iPhone the phone fills the screen and the
map opens from the **Map** button.

It exists so that design work starts from the real app instead of a mock that drifts. A feature is designed on top of
the mirror, Marc taps it on his phone, then the winner is ported to Swift and the mirror stays as the new baseline.

## Opening it

- Locally: open `docs/design/source/kit/app.html` in a browser. Fonts and art load from the repo (`FitFight/Fonts`,
  `FitFight/Assets.xcassets`), so keep it inside the repo.
- On a phone, from a pushed branch:
  `https://htmlpreview.github.io/?https://raw.githubusercontent.com/slooowshutter/FitFight/<branch>/docs/design/source/kit/app.html#<route>`
- The route after `#` is the navigation: the tab, then pushed screens, then `~` modals.
  `#fights/fight?id=duel/~editFight?id=duel` is the Eat it fight with its Edit sheet open. The map writes every route.
- Query options: `?shot=1` (the bare phone, for screenshots), `theme=day`, `scenario=empty` (see below), `admin=1`,
  `account=welcome|onboarding|restoring|unavailable`, `variant=<feature>:<option>` (a design option, see below).
- Fake data and settings persist in the browser. **Reset data** in the map restores them.

## Fake data

The people and fights are the ones in `FitFight/CompanionPreview.swift` (Alex is you; Leo, Nina, Sam and Theo; Step it
Up, Eat it, Walk Wars, The breakfast club, Coffee is on you). The map's data sets are the Companion preview display
states: Populated, Tied, Solo, Next round, Pending final sync, Finished, Empty, Loading, Cached / offline. Change the
Swift fixture and the mirror's `makeData` together.

## How the file is built

One file, no build step, plain HTML, CSS and JavaScript. A tiny script in `<head>` applies the theme before first
paint; everything else is one `<script>` at the end, because htmlpreview re-runs inline scripts in a way that can hide
one script's names from another. Inside it, each area is a `{ ... }` block that starts with a `// ═══ NN-area.js ═══`
header; search for it to find an area. An area shares helpers through `globalThis` (`FIGHTS.liveCard`,
`FEED.postCard`, `COMPANION_INTRO`...).

1. **Tokens**: the `tokens.json` palettes as CSS variables, verbatim. Never hardcode a colour.
2. **Kit**: `FF.button`, `FF.card`, `FF.groupedRow`, `FF.segmented`, `FF.field`, `FF.slide`, `FF.screen`... one function per
   `DesignSystem` Swift type, same name, same numbers. `icon("sf.symbol")` draws SF Symbols as strokes; add missing
   ones to `ICONS`.
3. **Shell**: fake data (`makeData`), navigation (`push`, `present`, `dismiss`, `back`, `setTab`, `go`), events, rendering
   of sheets, drawers, iOS alerts, action sheets and menus, and the map.
4. **Areas**: one block per part of the app (root and onboarding, Fights, fight detail, New, Feed, Feedback, Profile,
   companions, admin). Each registers its screens, actions and map links.

The pieces an area uses:

- `screen(id, { kind, render(p, ui) })`: `kind` is `root`, `push`, `sheet`, `drawer`, `cover`, `alert`, `actions` or
  `flow`. `p` holds the route's parameters; `ui` is that screen's own state (selected segment, typed text).
- `data-on="..."` on any button: `push:fight?id=duel`, `present:editFight?id=duel`, `back`, `close`, `tab:feed`,
  `set:filter=past`, `toggle:open`, or a named `action("join", (arg, ctx) => ...)`. Inputs use
  `FF.field(label, { bind: "name" })`.
- `D()` is the live fake data; change it and call `render()`.
- `links("Group", [["Label", "#route", { note, scenario, admin }]])` adds rows to the map. Every screen, sheet,
  dialog and notable state needs one.

## Proposing a feature

On the feature branch, build the new UI in `app.html` where it lives in the app: put `variant(...)` inside the area
block, next to the code it changes. The first option is **Today**, the app as it is, so Marc can compare; then one
option per idea, each today's screen plus one change (Marc rejects redesigns that change several things at once).
Register the options:

```js
variant("fights-streak", {
    title: "10K streak on Fights",
    note: "Where the streak sits on the Fights header.",
    options: [
        { id: "today", name: "Today", when: "The app as it is now." },
        { id: "title", name: "Next to the title", when: "Right if the streak should feel like part of your name." },
        { id: "steps", name: "Under today's steps", when: "Right if it should read as today's progress." },
    ],
    links: [["Fights", "#fights"], ["Streak drawer", "#fights/~streak"]],
});
// In the screen: V("fights-streak") === "steps" ? ... : ...
```

The map shows an **In progress** box with the options and links. List every screen that draws what you changed: a
shared card can appear on several screens (search for its helper). Every option uses the same fake data, and
`?variant=fights-streak:steps` opens one from a link. Touch no Swift while proposing.

## After Marc picks

1. Delete the `variant(...)` call, every `V(...)` check, and the losing options' code and CSS; the winner becomes
   plain mirror code.
2. Port it to Swift and add the `ReleaseNote`.
3. Update `MIRROR.matches` at the top of the script.

## Checking your work

- `node scripts/app-mirror-sweep.mjs` opens every map link in headless Chrome and taps every button, for every design
  option too, and reports exceptions, "Not mirrored yet" screens and unknown actions. Run it before pushing a mirror
  change; it must say "No problems". `--no-clicks` only opens the links (seconds instead of minutes).
- To look at one screen like the Simulator does (402×874 at 3x):
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=3 --window-size=402,874 --screenshot=/tmp/screen.png "file://$PWD/docs/design/source/kit/app.html?shot=1&theme=day#fights"`

## Keeping it equal to the app

Every native change that is visible updates the mirror in the same branch: new screens, copy, spacing, states,
removed features. When they disagree, Swift is the truth.

`scripts/app-mirror-check.sh` builds the app, launches it in this workspace's Simulator straight into each screen
it supports (Companion preview with `FF_SHOT`), renders the same route of the mirror in headless Chrome, and writes
side-by-side images to `.context/mirror-check/` (real app left). Look at them after a UI change. Screens the app cannot
be launched into (most sheets and dialogs) are checked against the Swift code.

## Limits

No server: writes change the fake data only. System UI (Sign in with Apple, Health permission, photo picker, share
sheet, StoreKit, Safari) is drawn as a stand-in; the Files picker is skipped (File attaches a sample file). SF
Symbols, charts and animations are close approximations, screens that load show their content at once, and Versions
lists the 12 newest release notes. The page is for design and review; it is not the signed-in web app at `/app`.
