# Locked decisions

These are the calls the ten reviews agreed on, or the ones a parent had to pick when they disagreed. Change them in a PR that updates this file, not in passing.

## Stack

| Decision | Why we will like this later |
| --- | --- |
| **Supabase = data plane** (Postgres, Auth, Storage, Realtime) | One SoR. RLS is the API wall. The anon key is public; that is fine. |
| **Vercel = compute plane** (ingest, crons, web, APNs) | One place for secrets, Zod, logs, invite pages. |
| **No Supabase Edge Functions as the app server** | Two runtimes = two settlement implementations. DB webhooks, if any, POST to Vercel. |
| **No Next.js BFF in front of iOS reads** | Phone reads PostgREST + Realtime. Vercel for trusted writes and jobs. |
| **iOS stays at `FitFight/`** | Moving the xcodeproj is the most expensive cosmetic refactor in this repo. |

## Data

| Decision | Why |
| --- | --- |
| **SoD on every quantity from L1 up** | Double-count, “where did 54 min come from”, anti-cheat later. |
| **L5 copy never in DB or as the wire format** | Design tab, localisation, “12 min behind Leo” going stale. |
| **Integer canonical units + cents** | No `Double` scores, no dollar `Int` that cannot split $10 four ways. |
| **Fight IANA timezone frozen at create** | One calendar for the table. Profile tz is only for You-tab “today”. |
| **`starts_at` inclusive, `ends_at` exclusive** (timestamptz) | No “is the last instant in?” |
| **Do not store `pot`** | Fixture bug: pot stayed 4× after a fifth join. `pot = buy_in × accepted`. |
| **Viewer `invited` is membership, not `fights.status`** | Same row is live for Leo and invited for Maya. |
| **`series_id` nullable on `fights` now** | Recurring is “new window,” not “reset the fight.” No `fight_series` table until that screen exists. |
| **Append-only samples; recompute the day from samples** | Retries stay correct. Never increment a counter in place. |

## Sync

| Decision | Why |
| --- | --- |
| **Phone uploads evidence; server writes L3/L4** | Cheat console + killed-app settlement. |
| **Steps = HealthKit only. Workouts/minutes = canonical sessions** | Strava writes into Health; summing both is the known mock bug. |
| **Do not score `appleExerciseTime` for v1 active minutes** | Watch-less users go to zero; Strava×Health doubles. Sum canonical session duration. |
| **6 hour grace after `ends_at`** | Schema review wanted 2h, money review 24h. 6h covers “I slept, I open in the morning” without hanging a week. Constant, not a UI. |
| **SwiftData caches L4 only, CloudKit off** | Apple: do not put HealthKit-derived data in iCloud. |
| **Background HK delivery is speed, not correctness** | Product works on app-open + nudge even before the entitlement. |

## Money

| Decision | Why |
| --- | --- |
| **IOU ledger, no processor, no rake, no escrow** | App Review 3.1.1 / 5.3. Adding Stripe changes the species of the app. |
| **One `settle()` for live projection and freeze** | Two maths = screenshot fights in iMessage. |
| **Invited ∉ pot** | They never agreed. |
| **Never-synced accepted member scores 0 and can lose** | Void-if-missing is a dodge. Void only if **nobody** in the committed set synced. |
| **Action stake is not proportional** | Already in the create UI. A dinner has no %. |
| **Sponsor credits are a different instrument later** | Company $20 never pays Leo. |
| **Buy-in cap $5–$100 in the API** | Mock stepper can grow forever. High-stakes screenshots look like a book. |

## Identity

| Decision | Why |
| --- | --- |
| **Sign in with Apple only** | Required the moment any other social login exists anyway. |
| **No friends table** | Roster = people you have fought. Handle search + invite link for everyone else. |
| **Invite token ≠ fight code** | `FIGHT-742` is a label. The link is an unguessable token that previews, not a standings credential. |
| **Join requires a session** | Share-sheet codes are not auth. |
| **Tombstone profiles, hard-delete samples** | History of other people’s fights stays; health uploads go. |

## Privacy (one product call vs a security review)

The privacy review wanted **no day-by-day series for opponents**. The approved fight-detail mock **is** “Every day so far.”

**v1 call:** accepted members of a fight see **daily totals** for the fight metric (the sport). They never see raw samples, GPS, HR, workout titles, or source mix (HK vs Strava). Invited-not-accepted see **no scores**. A richer health feed would be a new, opt-in product.

## Platform

| Decision | Why |
| --- | --- |
| **Two Supabase projects** (staging, prod) before the first real user | Preview + PR TestFlight must not hit prod. |
| **Vercel Preview has no prod `SERVICE_ROLE`** | Fail closed. |
| **Crons on Vercel Pro production only**, `CRON_SECRET` | Hobby cannot run minute settle. Dual cron (pg_cron + Vercel) will double-pay. |
| **Zod is TS source of truth; Swift is hand-mirrored; JSON fixtures in git** | Codegen when drift hurts. Linux agents cannot compile generated Swift. |
| **Wire JSON is camelCase in `/v1` Vercel routes; PostgREST is snake_case** | iOS talks to Vercel for ingest and to PostgREST for reads. Two adapters, documented. Do not invent a third. |
| **Feature flags in Postgres**, fail closed for writes | Design tab is not a flag system. |

## Explicitly rejected

| Idea | Why not |
| --- | --- |
| Client-computed settlement | Old TestFlight vs patched formula vs jailbreak. |
| Storing formatted kickers in Postgres | Copy and Design variants freeze. |
| Realtime on `metric_samples` | Health disclosure. |
| `REPLICA IDENTITY FULL` + DELETE on published tables | Realtime DELETE bypasses RLS. Soft-delete members. |
| Per-person midnight for fight days | Proportional settlement becomes mush. |
| Averaging HK + Strava | Merge, don’t mean. |
| Void fight if one person never opens the app | Loser tactic. |
| Friends graph / DMs / in-app Venmo in v1 | Platform ate the product. |
| Mixing sponsor credits into friend pots | Accounting + 5.3.3. |
| `AppModel` as the HealthKit + network owner | Split before fixtures die. |
| Moving Xcode to `apps/ios` | CI and pbxproj churn for a prettier tree. |
| Prisma/Drizzle as migration source | SQL files are what a phone-transcribed agent can write. |
