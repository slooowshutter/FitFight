# HealthKit Steps collection options

**Research and design proposal, 15 Sep 2026.** This is not an approved replacement
for the architecture. No app, API, schema, deployment, or release change is made
by this note. Apple behavior below was checked against official documentation and
WWDC. A two-viewer standings disagreement is reproduced below with invented data;
the reported family incident has not been matched to live data or device logs.

## Recommendation

Keep Apple's merged Steps statistics for scoring. First make the chart and
standings use the same Fight window, cutoff, revision, and finalization policy.
If incremental synchronization is useful, add anchored change tracking on the
phone to decide which statistics need refreshing. A server archive of all raw
samples is not required for that design.

This recommendation follows Apple's Steps synchronization example: detect added
and deleted samples with an anchored query, recalculate affected statistics, then
send the refreshed statistics to the server. Apple treats individual samples as
useful for some metrics but recommends cumulative statistics for this Steps use
case. [Apple WWDC20: Synchronize health data with HealthKit](https://developer.apple.com/videos/play/wwdc2020/10184/)

## What the three read paths provide

| Read path | Confirmed behavior | Consequence for FitFight |
| --- | --- | --- |
| Merged statistics | Statistics queries merge sources before calculating the result. | Use for the combined Apple Health Steps score. |
| Statistics separated by source | `separateBySource` produces independent source statistics. | Useful for inspecting sources; adding those totals can count overlapping activity twice. |
| Individual samples | Samples carry values and intervals; anchored queries return new samples and deleted-object identifiers. | Useful for change tracking and a deliberately specified audit system; they do not supply Apple's merged score. |

Apple documents the first two behaviors in [HKStatistics](https://developer.apple.com/documentation/healthkit/hkstatistics)
and [separateBySource](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions/separatebysource).
Sample and change behavior is documented in [HKSample](https://developer.apple.com/documentation/healthkit/hksample)
and [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery).

"Raw" means HealthKit records, not an individual timestamp for every footstep or
raw accelerometer measurements. Steps are cumulative quantity samples and Apple
can condense or coalesce them. A quantity sample can itself contain a series, and
its `quantity` returns the cumulative sum for cumulative types. Reading that one
value does not reconstruct the exact timing of every step. [Step count](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount),
[Quantity sample value](https://developer.apple.com/documentation/healthkit/hkquantitysample/quantity)

The cited Apple API contracts do not specify an algorithm FitFight can reproduce
to obtain Apple's exact cross-source merge. A custom merge would be a separate
scoring rule, with source priorities and overlap allocation to define and verify.
Storing more records does not establish equivalence to the Health app.

## Additions, corrections, and deletions

- HealthKit samples are immutable. The anchored-query result exposes new samples
  and deleted objects, with a new anchor for continuing from that position.
  [HKSample](https://developer.apple.com/documentation/healthkit/hksample),
  [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- An edit is generally represented by replacing an old sample. Apple describes
  delete-and-add for edits, and also provides sync identifiers and versions for
  apps managing records they write. These are not generic update webhooks for
  FitFight to receive from Apple. [WWDC20](https://developer.apple.com/videos/play/wwdc2020/10184/)
- A deleted object identifies the removed sample by UUID. It does not expose the
  original interval. Its metadata preserves only the sync identifier and sync
  version. Deleted objects are temporary and can be removed from HealthKit.
  [HKDeletedObject](https://developer.apple.com/documentation/healthkit/hkdeletedobject),
  [Deleted-object metadata](https://developer.apple.com/documentation/healthkit/hkdeletedobject/metadata)

**Proposed synchronization safeguards:** maintain a UUID-to-interval index if
refreshing only affected days. Otherwise refresh the relevant retained Fight
windows when a deletion cannot be located. Scope anchors to the user's local
HealthKit store and query configuration; never treat one device's cursor as a
global server cursor. Advancing a cursor must follow durable acknowledgement of
the corresponding data or durable pending work. Repeated deliveries must be
idempotent. Bootstrap, reinstall, changed query scope, and lost deletion history
need reconciliation. These are proposed application guarantees, not features
that an anchor implements for us.

## Raw data still depends on the phone

Observer queries tell the app that matching data changed; another query retrieves
the data. Background delivery wakes the app on the device. Apple documents an
hourly maximum frequency for iOS Steps background delivery, including when a more
frequent option is requested. This is a maximum wake frequency, not a guarantee
of an upload each hour. Background queries require device testing and are not
supported in the Simulator. [Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries),
[Background delivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))

Therefore a raw-sample backend would still need the phone to read and upload
changes, server persistence, a shared scoring result, and clients that refresh
that result. It would not by itself fix two phones showing different leaders.

HealthKit deliberately hides denied read permission. A successful empty query
cannot establish a true zero or permission denial, and history may be restricted
to a limited window. Both aggregate and raw implementations must preserve this
ambiguity. [Authorizing HealthKit access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

## Findings in the current repository

- [HealthKitStepAggregates.swift](../../FitFight/HealthKitStepAggregates.swift)
  reads separate Fight-window totals and calendar-day chart buckets. The current
  Steps path does not collect per-source statistics or raw samples.
- [HealthKitStepsStore.swift](../../FitFight/HealthKitStepsStore.swift) already
  observes Steps changes and refreshes aggregates. An anchor is not a prerequisite
  for corrections to reach a recalculated total.
- [healthkit-aggregates-supabase-query.ts](../../web/lib/supabase/queries/healthkit-aggregates-supabase-query.ts)
  marks earlier calendar days finalized, prevents later updates to those rows,
  and mirrors them into chart data. This can leave charts unchanged when Apple
  later corrects an earlier day, while a live Fight snapshot changes.

These code findings identify concrete divergence mechanisms. They do not prove
the exact numerical cause of the attached screenshot without the Fight's saved
data and synchronization history.

## Two phones showing different leaders

**Confirmed in a cloud fixture on 15 Sep 2026:** the production
`applyLocalHealthKitScores` and `orderedStandings` methods can make each viewer
appear to lead while they started from identical server data. The harness extracts
these methods from [AppModel.swift](../../FitFight/AppModel.swift), supplies small
data containers, and runs Swift 6.2.4 on Compiler Explorer with Swift 5 language
mode. It does not compile the iOS app or use HealthKit or real user data.

The relevant call ordering is in
[HealthKitStepsStore.swift](../../FitFight/HealthKitStepsStore.swift):
`onLocalAggregates` runs before `api.syncHealthKitSteps`. The callback wired in
[FitFightApp.swift](../../FitFight/FitFightApp.swift) replaces the viewer's score
and marks it just synced, then reranks against peers' cached scores. No server
acknowledgement is required for this local mutation.

Invented minimal reproduction:

| State | Phone A sees | Phone B sees |
| --- | --- | --- |
| Same initial server snapshot | A: 8,000; B: 9,000. B leads. | A: 8,000; B: 9,000. B leads. |
| Each applies its own local reading, before upload | A: 20,000; B: 9,000. A leads. | A: 8,000; B: 30,000. B leads. |
| Both receive the same refreshed snapshot | A: 20,000; B: 30,000. B leads. | A: 20,000; B: 30,000. B leads. |

Command: `python3 .context/repro_standings_disagreement.py`. Both runs compiled
and executed successfully, then intentionally exited 1 on the same assertion:

```text
FAIL: both phones show the same leader before server confirmation
```

Supporting code findings:

- `refreshFromServer` retains the current array after a failed request. Since
  that array can already contain local score changes, failure can retain mixed
  local and server values. Cached server snapshots also have no expiry check in
  `restoreCachedFights`.
- The inspected standings refresh paths run on foreground entry, manual refresh,
  relevant commands, or the current phone's own successful observer upload.
  There is no subscription or periodic standings fetch triggered by another
  participant's upload. The 60-second app timer checks release availability.
- [The aggregate writer](../../web/lib/supabase/queries/healthkit-aggregates-supabase-query.ts)
  awaits its transaction and updates stored member scores and ranks. The
  [snapshot reader](../../web/lib/supabase/queries/fight-snapshot-supabase-query.ts)
  reads stored member values for the caller's visible Fights. The refresh route
  is dynamic POST and [HTTP responses](../../web/lib/http.ts) use `no-store`.
  These paths do not establish a delayed database scoring queue. They also do
  not measure hosted database or network latency.

The two relevant backend test files passed all 33 tests:
`fight-snapshot-supabase-query.test.ts` and
`healthkit-aggregates-supabase-query.test.ts`. These tests use fixtures and
database doubles; they are not hosted database integration checks.

**Proposed correction:** show one server-confirmed standings snapshot at a time.
Keep newly read personal Steps separate until the shared snapshot arrives, expose
pending or stale state, and refresh visible standings when peers' scores change.
Preserve live Fight corrections and generate its chart from the same Fight
window, cutoff, and revision as its score. Raw sample ingestion would still need
all of these consistency guarantees.

No application code was changed by this investigation. No live database access
was configured in this workspace. The affected usernames, Fight/round, app builds,
timestamps, and per-device sync diagnostics are still needed to attribute the
reported incident or quantify hosted latency. Public health-endpoint timing would
not be a substitute for those signed-in operations.

## Boundaries and verification before implementation

Apple's `strictStartDate` filters samples by their start time; it is not a promise
to clip sample values to an interval. With no strict option, the sample predicate
matches overlapping samples. The docs reviewed do not establish every allocation
detail of a partially overlapping quantity sample or series. Do not describe a
boundary query as exact individual-step timing without device evidence.
[Strict start](https://developer.apple.com/documentation/healthkit/hkqueryoptions/strictstartdate),
[Sample date predicate](https://developer.apple.com/documentation/healthkit/hkquery/predicateforsamples(withstart:end:options:))

Proposed acceptance criteria:

1. Both participants receive the same standings at the same server revision.
2. A cumulative chart ends at its standings value for the same Fight cutoff.
   Consider cumulative checkpoints or another explicit reconciliation strategy;
   independently rounded day queries must not be assumed to sum exactly.
3. No pre-Fight or post-cutoff activity, future zero points, or stale earlier-day
   rows silently change what the chart means.
4. Late device data and deletions refresh all affected provisional projections.
   Fight finalization is explicit and preserves one consistent result and chart.
5. Device cases cover overlapping phone/watch records, samples crossing the Fight
   boundary, midnight, timezone/DST changes, empty or restricted access, deletion,
   reinstall, and interrupted delivery. Cloud tests preserve supported API
   request/response fixtures and replay behavior.

No hosted data, real HealthKit samples, or live two-phone behavior was tested for
this research. Any implementation requires the repository's normal compatibility
review and authorized deployment order. A raw archive would additionally need a
specific collection purpose and retention contract before collection expands.


## Implementation follow-up: 15 Sep 2026

Marc authorized automatic standings refresh. The prepared implementation removes
local score injection and refetches API snapshots after private Realtime
invalidations, subscription/reconnection, and replication readiness. It also
rejects superseded responses. Apple aggregate collection continues through the
existing upload contract. The daily-chart/window and historical-day correction
findings above remain outstanding. See [live standings evidence](../status.md#live-standings-prepared-15-sep-2026)
for cloud checks, compatibility, and deployment order.

## Chart consistency follow-up: 15 Sep 2026

Marc subsequently authorized fixing the chart discrepancy. The prepared change
saves Fight-window cumulative checkpoints on the same score snapshot, requires
the final point to equal the ranked total, and derives daily values from those
checkpoints. Provisional history is reread on sync; final history freezes with
its score. Old calendar rows are retained for installed clients but cannot supply
the new charts. See [current checks and rollout](../status.md#fight-charts-and-standings-prepared-15-sep-2026).
