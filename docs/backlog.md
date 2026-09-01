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

**Current scope lock (31 Aug 2026):** three tabs (**Fights**, **New**, **You**); direct exact-username invitations; Steps × highest total; a required typed loser action; 1-hour, 6-hour, and 1-day testing durations; and 3-day, 1-week, 2-week, or 1-month durations. Do not restore friends, Requests, money, other metrics, alternate scoring, or removed settings unless Marc explicitly reopens that scope.

## Urgent

### Freeze historical results against aggregation-code changes

Changing normalization, aggregation, or scoring code must not silently rewrite previously finalized history. Persist the calculation version, input revision, calculated value, and finalized time used for each historical day and Fight result. A new code version applies prospectively unless an explicit, audited backfill is approved.

Provider corrections, deletion tombstones, and late device syncs may still update an unfinalized day during its disclosed correction window. Once finalized, that day's stored result remains immutable except through an explicit audited correction. Decide the day-finalization boundary and correction window before relying on historical totals for recommendations or completed Fights.

### Verify account deletion before App Store submission

The backend now hard-deletes the profile, username, authentication rows, Health/Steps
data, uploads, friendships, invitations, memberships, and Fights the User created. It
removes the User from Fights owned by someone else. The phone clears its local Health
sync state. New Apple sign-ins store an encrypted revocation token; legacy accounts
without one still delete and receive the manual Apple Settings disconnect path.

Before App Store submission, configure the Sign in with Apple key and token-encryption
secret in both Vercel environments, then verify fresh sign-in and deletion on staging.

## Principle: server does the work

Most fight logic has to live on a server, not on the phone.

If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded. A server can: keep the fight window, send a push, settle scores once data is in.

The phone’s job is: show the UI, read Apple Health Steps when it is open (or briefly woken), and upload the required aggregates. Push notifications are not in the current scope.

**Last TestFlight:** 1 Sep 2026 — Fights appear immediately from the last successful update, refresh automatically when FitFight becomes active, and support pull-to-refresh on both the list and Fight detail. Failed refreshes keep existing Fights visible. Still `0.9.0`. Look for `0.9.0 · build N · staging`.

## Now

- Marc: Apple → On on the **new** develop Auth ([providers](https://supabase.com/dashboard/project/zstzbfocunthczzubggz/auth/providers)), client ID `com.fitfight.mvp`.
- Marc: add the Sign in with Apple key and a stable 32-byte token-encryption key to the staging and production Vercel environments before testing fresh sign-in or submitting.
- Marc: one Steps fight on staging. Exact username, required action, Apple Health, Start **once**.
- Participants on TestFlight Internal Testing. Same build, their own Apple IDs and usernames. Start with a 3-day Steps fight.

## Next

- **Validate aggregate-only Apple Health sync on staging.** Use two phones to confirm the authenticated request sends the server-issued Fight windows, the exact-window totals drive both standings, relevant merged daily buckets drive charts only, and no raw archive or Storage object is created.
- **Watch a real 3-day fight close.** Opening the app marks a due fight finished; the daily Vercel cron is the safety net. Proof is two phones: standings match, the Fight ends, and Steps after `ends_at` do not count. Do that before App Store.
- **Smoke-test every allowed duration.** Confirm New sends 1 hour, 6 hours, or 1, 3, 7, 14, or 30 days and the detail screen shows the typed action and correct end date.
- App Store when Marc says ship (`develop` → `main`).

## Later — outside the current product

These are parked ideas, not launch requirements. None may restore friends, Requests,
money, another metric, or alternate scoring without Marc explicitly reopening scope.

- **Restore bounded full-fidelity HealthKit ingestion only when a shipped feature needs it.** The MVP deliberately keeps only Apple's merged exact Fight-window totals and the relevant merged daily chart buckets. Before restoring raw samples, deletion anchors, per-source statistics, device/source metadata, or another archive transport, define the concrete product purpose, explicit Collection consent, bounded backfill, retention and deletion policy, edit/deletion reconciliation, provenance shown to Users, and operational size limits. Never calculate Steps by naïvely summing overlapping raw samples or source totals; Apple's merged aggregate remains the reference unless a reviewed Metric specification replaces it.
- **Advanced Fight-rule builder.** An explicitly advanced dynamic form for the full Measure × Score × Result model in [`fight-rules.md`](fight-rules.md). Earlier answers control which later fields appear: choosing workouts reveals workout-validity rules; choosing days reaching a value asks for the daily value; choosing Reach asks for the final goal. Show only reviewed compatible combinations, keep a plain-language summary visible, and validate the final object on the server. Do not make the Basic path feel like this form. No screen yet; do not build until moved up.
- **Natural-language Fight creation by text or voice.** A User types or records what they want—such as “10,000 Steps at least five days this week; everyone who does it succeeds.” Speech is transcribed when needed, then an LLM converts the request into the same validated Fight-rule object from [`fight-rules.md`](fight-rules.md) and fills the Advanced form. Ask a short follow-up when meaning is ambiguous; never invent an unsupported combination. Always show the completed form and plain-language rules for explicit confirmation before creating, inviting, or starting the Fight. Decide voice/transcript consent, retention, provider, cost, and failure behavior before implementation. No screen yet; do not build until moved up.
- **Recurring fights.** Same challenge every month (or every N days). Server rolls a new window when the last one ends. User does not recreate it by hand.
- **End-of-window sync nudge.** Push at the close of a period: open the app so steps / workouts can upload if they did not. Copy is “open so we can sync,” not a fake score. Server sends it; the phone cannot schedule this while killed.
- **Friend pokes (encourage / discourage).** A user writes a short line; the server sends a push to the friend. The notification is from FitFight; the words are from the friend. Apple does not ban this — every chat app does it. What they *do* require if people can send text: filter garbage, report, block, a way to reach us. Do not put health numbers or money in the lock-screen text. Rate-limit so it cannot become spam. “Discourage” is the spicy half — ship mute / block with it, or it becomes bullying and Apple *will* pull the app (guideline 1.2). Not a screen yet; do not invent one.
- **Dual challenge (one person vs the pool).** Not everyone racing the same metric. One person sets a personal goal — e.g. lose 10 kg in 2 months or 5 months, numbers from a connected scale at home. Other people put money into a pot. If they hit it, they take the pot. If they miss, still open: pot goes back to the backers, or the person pays them. Needs a weight/scale source, not only steps. Different shape from today’s “everyone on the card” fights. No screen yet; do not invent one.
- **Street stickers.** Stickers with a line like “do more sport / get fit and earn money at the same time,” plus a QR code. Marc sticks them everywhere. No design yet; do not invent one.
- **Company-sponsored credits.** Companies (example: Anthropic, OpenAI, or Blend) give credits or money to users who complete a challenge — enough sport / steps in a month, e.g. $20 of credits. Kind of philanthropy / partnership. No screen yet; do not invent one.
- **Challenge social / activity social.** The app is also a small social for friends on a fight. On a recurring bet (e.g. 45 kg dumbbell), people post progress — videos, what they did — to the challenge, both to share and to prove they made it. See what friends did, compare, encourage. Mix of Strava-style activity sharing and the bet. Fitness because people do it together.
  Also a place for accomplishments across apps and sports: one friend hikes, another bikes, they don’t share an app today so they send photos in Messages. Here they can post the activity, show the source (which provider), and share stats if they want. A friend feed even when you don’t have a fight with them. Maybe later: more than one feed (friends / fights / groups). Do not invent those tabs yet.
  Faking is fine for now. People will fake it. Figure anti-cheat later. For now: build the app, make it fun, let people share if they want. Steps Fights still come first; social is Later, not blocked on proof.

### SEO

- **One honest comparison page after launch.** After a real two-phone Fight is validated and FitFight is publicly downloadable, publish one useful page on FitFight’s official domain, such as “Best step challenge apps for competing with friends.” Actually test the included apps; show original screenshots, evaluation criteria, strengths, drawbacks, and the date tested; disclose that FitFight publishes the comparison. Do not create exact-match domains or mass-produced AI directory pages. Measure App Store visits, installs, and activated Fights—not impressions—and add more pages only if the first one brings qualified users.

## Ask first

Nothing is authorized here for the launch. Removed friends, Requests, notification
inbox, payouts, payment, extra settings, per-person goals, and alternate Fight rules
are not missing screens; they are out of scope.

## Done

The phone writes fights and Steps to staging after this PR is merged. See [`status.md`](status.md).

- Current launch shape: Fights, New, and You; direct exact-username Steps challenges; required loser action; 1/6-hour testing and 1/3/7/14/30-day durations; Privacy and Support links; essential settings only.
- Account deletion hard-deletes the account and owned Fights, removes participation elsewhere, clears local Health sync data, and supports encrypted Sign in with Apple token revocation.
- Historical v0.3 design port: four tabs, dark/light, 10 accents, fixture fights. Requests and extra accents were later removed.
- Historical Talk to the boss on Requests: private chat with Marc, emailed to him. Removed with Requests on 30 Aug 2026.
- Persistent GitHub `develop` + hosted Supabase branch `develop`.
- Sign in with Apple on You, real `profiles` handle, Apple Health Steps read on You → Data sources, Delete account under You → Settings.
- Smallest command API: create / invite / accept a Steps Fight. New adds participants by exact username and starts a real fight; fight detail Accept/Join accepts it.
- HealthKit Steps upload. Standings come from the database. Fights are no longer the fixture people.
- Fight closer: `live → awaiting_final_sync → final` on a server clock. Tests fake `now` for 1 / 3 / 7 / 14 day windows. Opening the app closes your due fights; Vercel cron closes the rest if nobody opens. No push yet.
- Welcome screen when signed out. Apple Sign In is the only way in; the tabs stay hidden until then.
- Username onboarding after sign-in. Phone-written Steps fights, HealthKit → `step_days`, standings from the database. Design tab removed.
- Approved HTML design-system port: Night/Day, Nunito, and reusable SwiftUI components. The internal showcase was removed from user settings.
