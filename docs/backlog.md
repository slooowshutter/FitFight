# Backlog

This is the product list. Not GitHub Issues, not Notion.

Marc talks from the phone: “put X on the backlog” or “do the next one.”
The agent edits this file, commits, opens a PR into `develop`.

| Column | Meaning |
| --- | --- |
| **Urgent** | Do before the next feature. Legal or data-integrity, not product. |
| **Now** | Next work. Pick from here unless Marc says otherwise. |
| **Next** | Decided, not started. |
| **Later** | Ideas. Do not build until Marc moves them up. |
| **Ask first** | Designed gaps. Do not invent the screen. |
| **Done** | Shipped enough to leave the list. |

Do not invent UI for anything in **Ask first** or undesigned Later items.

Honest works / doesn’t / next: [`status.md`](status.md). Read that before the next build.

[`system-design.md`](system-design.md) is the golden guide. Follow it. Do not implement the whole document. Production Metric is **Steps**; Active Minutes and Workout Count stay later.

## Urgent

### Map provider capabilities to canonical Metrics

Before adding another provider or Metric, define one versioned mapping from each provider's fields, units, aggregation semantics, and connection route to FitFight's canonical Metric definitions. Users choose a FitFight Metric such as Steps; they never choose a WHOOP, Strava, or HealthKit field directly. Each provider adapter declares which canonical Metrics it can supply, how it normalizes them, and which combinations are unsupported.

Discuss the capability matrix, direct-provider versus Apple Health copies, source precedence and deduplication, unit conversion, definition/version changes, and how the UI limits a Fight to Metrics supported by every selected source. Do not assume similarly named provider values mean the same thing.

### Freeze historical results against aggregation-code changes

Changing normalization, aggregation, or scoring code must not silently rewrite previously finalized history. Persist the calculation version, input revision, calculated value, and finalized time used for each historical day and Fight result. A new code version applies prospectively unless an explicit, audited backfill is approved.

Provider corrections, deletion tombstones, and late device syncs may still update an unfinalized day during its disclosed correction window. Once finalized, that day's stored result remains immutable except through an explicit audited correction. Decide the day-finalization boundary and correction window before relying on historical totals for recommendations or completed Fights.

### Really delete a user's data when they ask

Today "Delete account" is a soft delete. `delete_own_account()` sets `deleted_at`, renames the row to `Deleted User`, clears the avatar and time zone, and drops sessions, refresh tokens and identities. The row itself, the handle, and every metric observation stay in the database forever.

That is fine as an *account closure*. It is not a deletion, and under GDPR/CCPA a user asking to be deleted is entitled to actual erasure.

Needs deciding before it can be built — do not invent the answer:

- **What is erased vs kept.** Fights are shared objects. Removing a participant's rows rewrites other people's history and standings. The usual answer is erase the person (handle, display name, avatar, health data) and keep the fight with an anonymous placeholder, but that is Marc's call.
- **Health data is the sensitive part.** `private.metric_observations` holds step counts per user per day. That is the thing a regulator cares about; it should go regardless of what happens to fight rows.
- **Grace period?** Immediate, or 30 days then a purge job. A grace period means the soft delete stays as step one and a scheduled job does the real work.
- **The `auth.users` row** also needs removing via the admin API, which the current function does not do.

Also fix: a soft-deleted profile is invisible to its own owner, because `profiles_select_visible` is `using (deleted_at is null)`. The app now shows "Couldn't load your account" with a sign-out button instead of hanging, but the underlying state is still a user who is signed in and cannot read themselves.

## Principle: server does the work

Most fight logic has to live on a server, not on the phone.

If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded. A server can: keep the fight window, send a push, settle scores once data is in.

The phone’s job is: show the UI, read HealthKit / workouts when it is open (or briefly woken), upload, receive pushes.

**Last TestFlight:** 30 Aug 2026 — Apple Health now sends only Apple's merged Steps totals: exact Fight-window totals for standings and relevant daily buckets for charts. Raw HealthKit archives are no longer collected. Still `0.9.0`. Look for `0.9.0 · build N · staging`.

## Now

- Marc: Apple → On on the **new** develop Auth ([providers](https://supabase.com/dashboard/project/zstzbfocunthczzubggz/auth/providers)), client ID `com.fitfight.mvp`.
- Marc: one Steps fight on staging. Username, Apple Health, Start **once**.
- Friends on TestFlight Internal Testing. Same build. Their own Apple IDs. 3-day Steps fight after they have usernames.

## Next

- **Validate aggregate-only Apple Health sync on staging.** Use two phones to confirm the authenticated request sends the server-issued Fight windows, the exact-window totals drive both standings, relevant merged daily buckets drive charts only, and no raw archive or Storage object is created.
- **Watch a real 3-day fight close.** Opening the app marks a due fight finished; the daily Vercel cron is the safety net. Proof is two phones: standings match, the Fight ends, and Steps after `ends_at` do not count. Do that before App Store.
- App Store when Marc says ship (`develop` → `main`).

## Later

- **Restore bounded full-fidelity HealthKit ingestion only when a shipped feature needs it.** The MVP deliberately keeps only Apple's merged exact Fight-window totals and the relevant merged daily chart buckets. Before restoring raw samples, deletion anchors, per-source statistics, device/source metadata, or another archive transport, define the concrete product purpose, explicit Collection consent, bounded backfill, retention and deletion policy, edit/deletion reconciliation, provenance shown to Users, and operational size limits. Never calculate Steps by naïvely summing overlapping raw samples or source totals; Apple's merged aggregate remains the reference unless a reviewed Metric specification replaces it.
- **Sync Apple Health now from a Fight.** Add a clear manual sync action on the Fight detail screen so a participant can upload current HealthKit changes immediately and refresh the standings without leaving the Fight. Show the real state—syncing, up to date, or failed with retry—and do not promise that iOS background delivery is instant.
- **Basic Fight creation.** The default, simple path. Choose a Measure such as Steps and compete directly on its total: the highest value wins. Keep the Measure × Score × Result machinery hidden. This produces the simplest valid object from [`fight-rules.md`](fight-rules.md), currently Steps × Total × Highest. No screen yet; do not build until moved up.
- **Advanced Fight-rule builder.** An explicitly advanced dynamic form for the full Measure × Score × Result model in [`fight-rules.md`](fight-rules.md). Earlier answers control which later fields appear: choosing workouts reveals workout-validity rules; choosing days reaching a value asks for the daily value; choosing Reach asks for the final goal. Show only reviewed compatible combinations, keep a plain-language summary visible, and validate the final object on the server. Do not make the Basic path feel like this form. No screen yet; do not build until moved up.
- **Natural-language Fight creation by text or voice.** A User types or records what they want—such as “10,000 Steps at least five days this week; everyone who does it succeeds.” Speech is transcribed when needed, then an LLM converts the request into the same validated Fight-rule object from [`fight-rules.md`](fight-rules.md) and fills the Advanced form. Ask a short follow-up when meaning is ambiguous; never invent an unsupported combination. Always show the completed form and plain-language rules for explicit confirmation before creating, inviting, or starting the Fight. Decide voice/transcript consent, retention, provider, cost, and failure behavior before implementation. No screen yet; do not build until moved up.
- **Replay and recurring fights.** When a fight ends, a Redo / Replay button starts the same challenge again; people accept the new window. Recurring is the always-on version: same fight every week (or every N days), server recreates it when the last one ends, so you do not rebuild a weekly steps fight with your wife by hand. Recurring series also get a tiny history: how many times each person has won or lost across previous windows, a ranking of this challenge over time. No extra screens yet; do not invent one.
- **End-of-window sync nudge.** Push at the close of a period: open the app so steps / workouts can upload if they did not. Copy is “open so we can sync,” not a fake score. Server sends it; the phone cannot schedule this while killed.
- **Friend pokes (encourage / discourage).** A user writes a short line; the server sends a push to the friend. The notification is from FitFight; the words are from the friend. Apple does not ban this — every chat app does it. What they *do* require if people can send text: filter garbage, report, block, a way to reach us. Do not put health numbers or money in the lock-screen text. Rate-limit so it cannot become spam. “Discourage” is the spicy half — ship mute / block with it, or it becomes bullying and Apple *will* pull the app (guideline 1.2). Not a screen yet; do not invent one.
- **Dual challenge (one person vs the pool).** Not everyone racing the same metric. One person sets a personal goal — e.g. lose 10 kg in 2 months or 5 months, numbers from a connected scale at home. Other people put money into a pot. If they hit it, they take the pot. If they miss, still open: pot goes back to the backers, or the person pays them. Needs a weight/scale source, not only steps. Different shape from today’s “everyone on the card” fights. No screen yet; do not invent one.
- **Street stickers.** Stickers with a line like “do more sport / get fit and earn money at the same time,” plus a QR code. Marc sticks them everywhere. No design yet; do not invent one.
- **Company-sponsored credits.** Companies (example: Anthropic, OpenAI, or Blend) give credits or money to users who complete a challenge — enough sport / steps in a month, e.g. $20 of credits. Kind of philanthropy / partnership. No screen yet; do not invent one.
- **Challenge social / activity social.** The app is also a small social for friends on a fight. On a recurring bet (e.g. 45 kg dumbbell), people post progress — videos, what they did — to the challenge, both to share and to prove they made it. See what friends did, compare, encourage. Mix of Strava-style activity sharing and the bet. Fitness because people do it together.
  Also a place for accomplishments across apps and sports: one friend hikes, another bikes, they don’t share an app today so they send photos in Messages. Here they can post the activity, show the source (which provider), and share stats if they want. A friend feed even when you don’t have a fight with them. Maybe later: more than one feed (friends / fights / groups). Do not invent those tabs yet.
  Faking is fine for now. People will fake it. Figure anti-cheat later. For now: build the app, make it fun, let people share if they want. Steps Fights still come first; social is Later, not blocked on proof.
- **Stompers-style race line (not a high-score list).** Copy the feel of [Stompers](https://www.stompers.com/): animated people running on a line, not a ranked table. When you open a fight, stretch the lowest person’s score to the left of the screen and the highest to the right, then place everyone else on that min–max scale by their actual score. The line is the standing; do not make it a scoreable high-score board. Running animation is the point. No extra screens yet; do not invent one.
- **Animal avatars.** On join you pick an animal (panda / raccoon vibe). One locked artistic style as a small icon, used on You, home, everywhere. The animal can vaguely look like the person. Every 7 days regenerate the same animal from last week’s average movement / goals: more muscular if they hit it, fatter if they didn’t. When a fight starts, generate one cover of everyone’s animals fighting together. Art direction only; no screens yet; do not invent one.
- **School / university fights.** A class or a school runs a fight. Each person does their own sport. Teachers and the school do not get a feed of everything. They only need “did this person do enough.” Phone-in-class is one possible culture hook (if you want the phone, you are in the fight), not a designed screen. Same shape for universities. Wellness as part of how the school works, not a PE gradebook. Calories is a possible metric later. Production metric stays Steps for now. No screens yet; do not invent one.
- **Company yearly culture fights.** A company runs a long fight (a year, not a week) as how they work, not a sponsor pot. Different from company-sponsored credits. People still do their own sport. The company only needs “did they do enough,” not a spy dashboard. No screens yet; do not invent one.

### SEO

- **One honest comparison page after launch.** After a real two-phone Fight is validated and FitFight is publicly downloadable, publish one useful page on FitFight’s official domain, such as “Best step challenge apps for competing with friends.” Actually test the included apps; show original screenshots, evaluation criteria, strengths, drawbacks, and the date tested; disclose that FitFight publishes the comparison. Do not create exact-match domains or mass-produced AI directory pages. Measure App Store visits, installs, and activated Fights—not impressions—and add more pages only if the first one brings qualified users.

## Ask first

From [`design/source/INVENTORY.md`](design/source/INVENTORY.md) — honest holes, no mock-up:

- Notifications inbox (the bell has no destination)
- Request compose + request thread
- Profile edit, settings sub-screens, payouts
- HealthKit permission prompts (we request on username continue and on Data sources tap; no extra designed screen)
- Per-person goals in create (data model allows it; UI is one shared goal)
- Settle-up / payment at the end of a fight

## Done

The phone writes fights and steps to staging after this PR is merged. See [`status.md`](status.md).

- v0.3 design port: four tabs, dark/light, 10 accents, fixture fights.
- Talk to the boss on Requests: private chat with Marc, emailed to him.
- Persistent GitHub `develop` + hosted Supabase branch `develop`.
- Sign in with Apple on You, real `profiles` handle, Apple Health Steps read on You → Data sources, Delete account under You → Settings.
- Smallest command API: create / invite / accept a Steps Fight. New fight starts a real fight; fight detail Accept/Join accepts it.
- HealthKit Steps upload. Standings come from the database. Fights are no longer the fixture people.
- Fight closer: `live → awaiting_final_sync → final` on a server clock. Tests fake `now` for 1 / 3 / 7 / 14 day windows. Opening the app closes your due fights; Vercel cron closes the rest if nobody opens. No push yet.
- Welcome screen when signed out. Apple Sign In is the only way in; the tabs stay hidden until then.
- Username onboarding after sign-in. Phone-written Steps fights, HealthKit → `step_days`, standings from the database. Design tab removed.
- Approved HTML design-system port: Night/Day, Nunito, reusable SwiftUI components, all product screens rebuilt, and the complete showcase under You → Settings.
