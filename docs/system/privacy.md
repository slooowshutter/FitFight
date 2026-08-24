# Privacy, RLS, App Review

The IPA contains the anon key. Anyone with a user JWT is PostgREST. SwiftUI is not a security boundary.

## Threat

Stolen JWT: read whatever RLS allows, subscribe to Realtime, call RPCs. They will not use your screens.

RLS goal: nobody else’s **health evidence**, no rewrite of settlement, no join without invite, no live sample tap. RLS is not anti-cheat (v1 allows faking).

`service_role` only on Vercel jobs. If a user GET is “Edge Function + service role + filter in JS,” RLS is already gone.

## What opponents may see

Fair play needs a **score**, not a lifestyle.

| Data | Self | Accepted opponent | Invited, not in | Stranger |
| --- | --- | --- | --- | --- |
| Name, avatar, handle | yes | yes | yes | no |
| Window total + today (fight metric) | yes | yes | **no** | no |
| Day-by-day totals | yes | **yes** (the designed card) | no | no |
| Raw workouts, GPS, HR, titles | device | **never** | never | never |
| HK vs Strava mix | You tab | **never** | never | never |
| Exact last sync time | yes | `live / stale / missing` | no | no |
| Money line | yes | yes | stake copy only | no |

Invite screens in the mock that show a live board are **not** the API.

Weight later: hit/miss boolean, never a kg series.

## HealthKit

Read only. Prompt **when joining/creating a live fight**, types for **that metric only**.

| Fight | Types | Upload |
| --- | --- | --- |
| steps | `stepCount` | sums |
| active minutes | workouts we can justify | canonical session duration |
| workouts | `HKWorkout` count | count |

Never request HR, sleep, routes, clinical, nutrition until a fight type needs them (new string + re-prompt).

Usage string must name the types. Privacy Nutrition: Health used for app function, not tracking, not ads.

Local HK cache: exclude from backup. No CloudKit. No samples in Sentry.

## Realtime

Do not publish `metric_samples`. Publish standings/days **without** `audit`. Per-fight channel. Unsub on leave. Soft-delete members (DELETE payloads are a leak class).

Push alerts: **no health numbers, no money**. “Open so we can sync.” / “Your fight ended.” / “{name} challenged you.”

Poke body later: friend’s filtered text, still no scores/$. Report/block/rate-limit **on the same day** pokes ship (guideline 1.2). Requests compose the same.

No user images in v1 (CSAM pipeline before that).

## Secrets and cron

Public: URL, anon key, display codes.

Never in git/IPA/`NEXT_PUBLIC_`: service role, APNs, Strava secret, `CRON_SECRET`.

Cron: `Authorization: Bearer CRON_SECRET`, constant-time compare. One scheduler (Vercel). Idempotent settle.

Preview: no prod service role.

## Deletion and export

In-app delete. Export: own profile, memberships, **own** totals, own UGC, receipts you are party to. Not opponents’ samples.

Legal basis: contract for accounts; **explicit consent** for HealthKit upload. GDPR Art. 9 likely. DPA with Supabase and Vercel.

## Age and money

- App Store **17+**
- Staked ($ ) fights: **18+** attestation before create/join when that screen exists
- Not a gambling operator: IOU, settle outside, no IAP for pots, no rake, no cash-out
- Bragging-only is the conservative first production flag if review or law is unclear

## Settlement audit

Append-only freeze snapshot (inputs, hash, nets, `algorithm_version`). Late HK after freeze does not rewrite. Members may read the **receipt** (rules + window totals at freeze), not ingest payloads.

## Logging

Do not log JWTs, Authorization, sample bodies, or “Maya winning by 12 min” breadcrumbs.
