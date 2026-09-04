# Recurrence — clocks only

Status: Later. Do not build. No screens.

Product decision (three products, Station F vs wife, must / don’t): [`proposals/themed-recurring-fights.md`](proposals/themed-recurring-fights.md).

This page is only the clock: a Fight stays a Fight. Recurrence is a **series** that **mints new Fights**. It never edits a child’s window, timezone, rules, or final result.

Today’s “1 week” is **rolling** (create-time plus 7 days). League “weekly” is a calendar week. They are not the same duration.

## Recommendation

**Station F — calendar weeks in the series timezone, season of N, organizer stop.**

Series TZ is the venue (`Europe/Paris`), copied onto each child at mint. Periods are `[Mon 00:00, next Mon 00:00)` in that zone — civil calendar, not `7 × 86400`. Mint the next Fight at previous **`ends_at`**, even if last week is still `awaiting_final_sync`. Windows **abut**; grace is a sync tail, not extra scoring. Stop prevents future mints only; the live Fight still closes on its own clock. Always-on is the same loop with no N — offer it, don’t default a workplace to it.

**Wife — Replay only.** Redo copies rules; people accept the new window. No series, no Monday snap. If they later want auto, mint the next **rolling** window at `ends_at` until someone stops — still not “wait until `final`.”

## Compare

1. **Manual Replay.** Safest. Matches immutability and late-join-from-`starts_at`. Fine for two people. Not a league.

2. **Mint when previous finalizes.** Wrong clock. 24h grace delays the next week; a stuck HealthKit upload blocks the league. Reject as trigger. Mint at `ends_at`.

3. **Calendar-aligned weeks.** Right for Station F. Shared Monday. DST-safe if Paris civil midnight is the boundary. Next period exists while last week finalizes.

4. **Overlapping live windows.** Bad: same steps score twice. Abutting `[starts_at, ends_at)` plus a grace tail is not overlap. An event at `ends_at` belongs only to the next Fight.

5. **Season of N then stop.** Right workplace/campus default. History is N ordinary Fights.

6. **Always-on until stop.** Same mint as (3) or rolling (2′) with no N. A forgotten series keeps querying HealthKit.

## Must-haves

- Each child is a normal Fight: same state machine, half-open window, server clock, immutable TZ/rules after lock, late joiners scored from **that** Fight’s `starts_at`.
- Idempotent mint: unique `(series_id, starts_at)`. Phone never inserts the next row.
- Mint at the window boundary, not at `final`. Incomplete previous must not skip or duplicate the next period.
- Template edits apply only to Fights not yet `live`.
- Cron does mint + close. Push stays out of scope.

## Nice-to-haves

- Win/loss view over child `final` rows only.
- Standing roster auto-invites; acceptance still per Fight unless Marc wants standing yes.
- Pause one period; rebuild a still-`scheduled` unaccepted child after a template change.

## Should-nots

Stretch a Fight instead of minting. Wait for everyone to sync before next week. Use device or traveler TZ for league boundaries. Count one step in two live windows. Replace the Fight with a series score. Treat rolling 7 days and calendar weeks as one duration.

## Quirks

**DST.** Monday 00:00 `Europe/Paris`. Spring-forward weeks are 167h, fall-back 169h. Do not add 168 hours to UTC.

**Grace vs next start.** At `ends_at`: N → `awaiting_final_sync`, N+1 → `live`. The phone already uploads both. Late HealthKit for N must fall inside N’s window. N+1 steps never enter N.

**Unsynced on N.** Finalize N with the incomplete rule at grace. They may still join N+1. Do not pause the league.

**Join mid-week.** Accepting this week’s Fight keeps today’s full-window backfill. Adding to the **roster** defaults to the **next** period, unless they explicitly join the live Fight.

**Travel.** Scoring days stay Paris. Series TZ changes affect the next mint only.

**Failed finalization.** Closer still finalizes at grace. Mint does not wait. Stuck past grace is a closer bug, not a skipped week.

**Two next Fights.** Unique constraint; when P goes live, ensure P+1 is `scheduled`. Retries no-op.

**Week → month.** First period not yet `live`. If P+1 is already accepted-scheduled, wait until P+2.

**History.** Series stats are a view. Each Fight stays an ordinary Fight.

**“1 month”** today is 30 days, not a civil month. Don’t silently upgrade it.

## Marc

1. Station F: Mon 00:00 Paris, or Mon 09:00?
2. First season: how many weeks, or always-on?
3. Thursday join: next Monday only, or also this week with backfill?
4. Accept each week, or standing membership?
5. Same loser action every week, or re-type?
6. If you leave Station F, who owns the series?
7. Wife: Replay enough, or auto after `ends_at`?
8. If auto for two people: keep the start weekday/time, or snap to Monday?
9. Station F + wife the same week? (Yes: two Fights.)
10. Incomplete-final weeks: count in series ranking, or omit?
