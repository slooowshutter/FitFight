# Backlog

This is the product list. Not GitHub Issues, not Notion.

Marc talks from the phone: “put X on the backlog” or “do the next one.”
The agent edits this file, commits, opens a PR.

| Column | Meaning |
| --- | --- |
| **Now** | Next work. Pick from here unless Marc says otherwise. |
| **Next** | Decided, not started. |
| **Later** | Ideas. Do not build until Marc moves them up. |
| **Ask first** | Designed gaps. Do not invent the screen. |
| **Done** | Shipped enough to leave the list. |

Do not invent UI for anything in **Ask first** or undesigned Later items.

## Principle: server does the work

Most fight logic has to live on a server, not on the phone.

If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded. A server can: keep the fight window, send a push, settle scores once data is in.

The phone’s job is: show the UI, read HealthKit / workouts when it is open (or briefly woken), upload, receive pushes.

## Now

- Real fights, not fixtures. People, scores, and money lines have to come from somewhere other than the mock.

## Next

- Backend. Accounts, fights, scores, pushes. Nothing below works without this.
- HealthKit (or another data source) so a fight has real numbers.

## Later

- **Recurring fights.** Same challenge every month (or every N days). Server rolls a new window when the last one ends. User does not recreate it by hand.
- **End-of-window sync nudge.** Push at the close of a period: open the app so steps / workouts can upload if they did not. Copy is “open so we can sync,” not a fake score. Server sends it; the phone cannot schedule this while killed.
- **Friend pokes (encourage / discourage).** A user writes a short line; the server sends a push to the friend. The notification is from FitFight; the words are from the friend. Apple does not ban this — every chat app does it. What they *do* require if people can send text: filter garbage, report, block, a way to reach us. Do not put health numbers or money in the lock-screen text. Rate-limit so it cannot become spam. “Discourage” is the spicy half — ship mute / block with it, or it becomes bullying and Apple *will* pull the app (guideline 1.2). Not a screen yet; do not invent one.
- **Dual challenge (one person vs the pool).** Not everyone racing the same metric. One person sets a personal goal — e.g. lose 10 kg in 2 months or 5 months, numbers from a connected scale at home. Other people put money into a pot. If they hit it, they take the pot. If they miss, still open: pot goes back to the backers, or the person pays them. Needs a weight/scale source, not only steps. Different shape from today’s “everyone on the card” fights. No screen yet; do not invent one.
- **Street stickers.** Stickers with a line like “do more sport / get fit and earn money at the same time,” plus a QR code. Marc sticks them everywhere. No design yet; do not invent one.
- **Company-sponsored credits.** Companies (example: Anthropic, OpenAI, or Blend) give credits or money to users who complete a challenge — enough sport / steps in a month, e.g. $20 of credits. Kind of philanthropy / partnership. No screen yet; do not invent one.

## Ask first

From [`design/source/INVENTORY.md`](design/source/INVENTORY.md) — honest holes, no mock-up:

- Notifications inbox (the bell has no destination)
- Request compose + request thread
- Profile edit, settings sub-screens, payouts
- Sign-in, onboarding, HealthKit permission prompts
- Per-person goals in create (data model allows it; UI is one shared goal)
- Settle-up / payment at the end of a fight

## Done

- v0.3 design port: four tabs, dark/light, 10 accents, fixture fights.
