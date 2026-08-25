# Backlog

This is the product list. Not GitHub Issues, not Notion.

Marc talks from the phone: “put X on the backlog” or “do the next one.”
The agent edits this file, commits, opens a PR into `develop`.

| Column | Meaning |
| --- | --- |
| **Now** | Next work. Pick from here unless Marc says otherwise. |
| **Next** | Decided, not started. |
| **Later** | Ideas. Do not build until Marc moves them up. |
| **Ask first** | Designed gaps. Do not invent the screen. |
| **Done** | Shipped enough to leave the list. |

Do not invent UI for anything in **Ask first** or undesigned Later items.

[`system-design.md`](system-design.md) is the golden guide. Follow it. Do not implement the whole document. Production Metric is **Steps**; Active Minutes and Workout Count stay later.

## Principle: server does the work

Most fight logic has to live on a server, not on the phone.

If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded. A server can: keep the fight window, send a push, settle scores once data is in.

The phone’s job is: show the UI, read HealthKit / workouts when it is open (or briefly woken), upload, receive pushes.

## Now

- Marc: GitHub Actions variables `SUPABASE_STAGING_URL`, `SUPABASE_STAGING_PUBLISHABLE_KEY`, `FITFIGHT_API_URL` (and `FITFIGHT_API_PRODUCTION_URL` later). Apple Sign In On on the Supabase `develop` branch.
- Marc: Vercel project, root `web/`, Preview + develop → Supabase develop secret; Production → main project. Also set `CRON_SECRET` on Vercel (Preview + Production). Never paste it in chat.
- Friends on TestFlight. Marc adds them as internal testers. Same build. They sign in with their own Apple ID (staging users, not production). Start a 3-day Steps fight with one friend and leave it running.

## Next

- **Watch a real 3-day fight close.** Clock tests already fake 1 / 3 / 7 / 14 days. The closer job and app-open sync are in. The missing proof is two phones: fight ends, someone opens or cron runs, standings go final, steps after `ends_at` do not count. Do that before App Store.
- Try the two-phone loop on TestFlight (`develop` + staging API). Then App Store review when Marc says ship (`develop` → `main`).

## Later

- **Recurring fights.** Same challenge every month (or every N days). Server rolls a new window when the last one ends. User does not recreate it by hand.
- **End-of-window sync nudge.** Push at the close of a period: open the app so steps / workouts can upload if they did not. Copy is “open so we can sync,” not a fake score. Server sends it; the phone cannot schedule this while killed.
- **Friend pokes (encourage / discourage).** A user writes a short line; the server sends a push to the friend. The notification is from FitFight; the words are from the friend. Apple does not ban this — every chat app does it. What they *do* require if people can send text: filter garbage, report, block, a way to reach us. Do not put health numbers or money in the lock-screen text. Rate-limit so it cannot become spam. “Discourage” is the spicy half — ship mute / block with it, or it becomes bullying and Apple *will* pull the app (guideline 1.2). Not a screen yet; do not invent one.
- **Dual challenge (one person vs the pool).** Not everyone racing the same metric. One person sets a personal goal — e.g. lose 10 kg in 2 months or 5 months, numbers from a connected scale at home. Other people put money into a pot. If they hit it, they take the pot. If they miss, still open: pot goes back to the backers, or the person pays them. Needs a weight/scale source, not only steps. Different shape from today’s “everyone on the card” fights. No screen yet; do not invent one.
- **Street stickers.** Stickers with a line like “do more sport / get fit and earn money at the same time,” plus a QR code. Marc sticks them everywhere. No design yet; do not invent one.
- **Company-sponsored credits.** Companies (example: Anthropic, OpenAI, or Blend) give credits or money to users who complete a challenge — enough sport / steps in a month, e.g. $20 of credits. Kind of philanthropy / partnership. No screen yet; do not invent one.
- **Challenge social / activity social.** The app is also a small social for friends on a fight. On a recurring bet (e.g. 45 kg dumbbell), people post progress — videos, what they did — to the challenge, both to share and to prove they made it. See what friends did, compare, encourage. Mix of Strava-style activity sharing and the bet. Fitness because people do it together.
  Also a place for accomplishments across apps and sports: one friend hikes, another bikes, they don’t share an app today so they send photos in Messages. Here they can post the activity, show the source (which provider), and share stats if they want. A friend feed even when you don’t have a fight with them. Maybe later: more than one feed (friends / fights / groups). Do not invent those tabs yet.
  Faking is fine for now. People will fake it. Figure anti-cheat later. For now: build the app, make it fun, let people share if they want. Steps Fights still come first; social is Later, not blocked on proof.

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
- Talk to the boss on Requests: private chat with Marc, emailed to him.
- Persistent GitHub `develop` + hosted Supabase branch `develop`.
- Sign in with Apple on You, real `profiles` handle, Apple Health Steps read on You → Data sources, Delete account under You → Settings.
- Smallest command API: create / invite / accept a Steps Fight. New fight starts a real fight; fight detail Accept/Join accepts it.
- HealthKit Steps upload. Standings come from the database. Fights are no longer the fixture people. Design tab still previews the old mock.
- Fight closer: `live → awaiting_final_sync → final` on a server clock. Tests fake `now` for 1 / 3 / 7 / 14 day windows. Opening the app closes your due fights; Vercel cron closes the rest if nobody opens. No push yet.
