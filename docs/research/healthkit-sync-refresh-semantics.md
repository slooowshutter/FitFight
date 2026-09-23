# HealthKit refresh and synchronization semantics

**Research from 20 Sep, implementation prepared 23 Sep 2026.** This note records
Apple's public contracts and the chosen synchronization design. The implementation
is on `explain-activity-sync-tables`; no migration, backend, native build, or privacy
copy from this branch has been deployed. It complements
[the earlier Steps collection research](healthkit-steps-collection-options.md).

## Implementation decision, 23 Sep

Individual HealthKit quantity and category samples stay on the phone. They are
read locally only to identify changed days. The server receives Apple's merged
Steps and other supported daily totals, exact Fight-window Steps readings and
checkpoints, workout summaries, and explicit workout deletion UUIDs. The
serialized received records enter `private.activity_raw`; the resolver publishes
current measurements to `private.activity_metrics`. Workout-derived day metrics
never add to Apple's merged daily values.

The app rereads the most recent 40 civil days on each sync. First sync imports
all accessible merged daily history in acknowledged pages of at most 1,000 days,
plus accessible workouts through an all-history anchored query. Each daily type
has an anchored local change query with a fixed start at bootstrap minus 40 days;
its anchor advances after the affected merged days are acknowledged. Workout
anchors advance after summaries and deletion UUIDs are acknowledged. Late
changes earlier than that fixed daily predicate may be missed. Deleted objects
are temporary in HealthKit, so a long absence can also miss a workout deletion.

The existing `/api/v1/healthkit/steps` contract stays for installed builds. The
new app sends Fight readings there, then sends daily totals and workouts through
`POST /api/v1/healthkit/activity`. The backend retains old readers and writes a
legacy Steps mirror. A bounded resolver and the close-fights worker retry saved
pending records. Personal history can be corrected; final Fight results remain
frozen. Hosted CI proves code and disposable database behavior, while actual
background delivery and HealthKit authorization still require device checks.

The sections below preserve the original research and pre-change baseline. This
implementation decision supersedes proposals to upload individual samples or
sample deletions.

## Confirmed requirements from Marc, 20 Sep

The requested architecture has two shared activity stores:
`private.activity_raw` for received provider records and changes, followed by
`private.activity_metrics` for their normalized measurements. Workouts and Steps
use this same path. The requirements below are agreed direction, not implemented
behavior or authorization for a deployment or destructive migration.

- Register observation and background delivery for every supported HealthKit
  sample type FitFight reads, including workouts. Derived metrics such as weekly
  Steps or workout count are invalidated by their underlying sample types; they
  do not have separate HealthKit observers. Where Apple does not support delivery
  for a type, retain foreground/manual collection and report that limitation.
  Registration remains active while collection is enabled. iOS controls actual
  delivery and execution; this does not promise a continuously running process.
- Foreground, manual, and background triggers enter the same collection and
  processing flow, coalescing concurrent work without losing another type's
  pending changes. Each type has its own acknowledged collection checkpoint.
- Authenticate and validate the record envelope before intake. Commit the
  serialized source record and pending processing state before normalizing it.
  A failed transformation leaves the original available for inspection/replay.
- Preserve source IDs and relevant source revision/change ordering. Raw history
  may retain multiple distinct versions or deletion events for one activity.
  Exact retries do not need another physical raw row. Retried requests and two
  devices reporting the same UUID must produce the same effective metrics.
- The TypeScript processing pipeline resolves record identity, corrections and
  explicit deletions; extracts units, intervals and scope; and replaces the
  affected current measurements. Never increment a user's total merely because
  another upload arrived. A delayed replay must not resurrect a deleted record.
- Each measurement links to its input and calculation version. Scope separates
  sample/workout/day/Fight-window measurements. Raw samples, workout measurements
  and already-merged daily totals are not interchangeable summation inputs.
  Official Steps continue using Apple's merged statistics, retained as labeled
  input records, rather than server sums of overlapping source samples.
- Track pending, processing, processed and failed work with processing version
  and error information. Received and processed are distinct acknowledgements.
  A backend worker processes persisted pending work in bounded batches and
  resumes unfinished work after interruption. The UI must not mark all activity
  current when only Steps succeeded.
- Publish affected metrics and each score/chart revision consistently. All
  readers consume the designated server measurements for their requested scope.
  Personal historical metrics remain correctable; completed Fight outcomes
  retain their existing finalization policy.

Acceptance checks include repeated delivery, two devices reporting the same
record, deletion followed by stale replay, a historical correction, processing
failure after intake, interrupted pages, and no double counting between workout
and daily totals. Each supported HealthKit sample type also needs a verified
observer registration path; actual background delivery requires device checks.

## Refresh strategy, agreed 22 Sep

Refresh is split by data kind. Apple's merged totals are reread from the start
of their window on every sync. Individual records are collected as anchored
changes since the last acknowledged checkpoint. Both enter `activity_raw` and
the same resolver.

| Data | Each foreground, manual, or background sync | Reason |
| --- | --- | --- |
| Merged totals: Fight Steps, chart checkpoints, daily totals | Statistics query from window start to the collection cutoff | A few values per window. Catches every change inside it, including source-priority changes that add or delete no record |
| Records: workouts and quantity samples | Anchored query: additions and explicit deletions since the saved checkpoint | Saved samples are immutable, so rereading known records returns identical data |
| First sync, reinstall, new device, lost checkpoint | Full anchored read of each type's authorized history, paged | Establishes the checkpoint |

- Totals: retain the exact start-to-cutoff merged Steps query for each active
  Fight. Store each reading as a labeled total with its window boundaries, time
  zone, and cutoff. The resolver selects the latest reading per window and never
  sums readings.
- Records: rereading a month of about 20 sample types would resend thousands of
  unchanged records every sync, while background work is cancelled after 25
  seconds. Anchored results carry explicit deletions. A full reread would infer
  deletion from absence, and denied read access returns empty results without
  an error.
- A new or deleted record dated outside the reread windows marks its day as
  changed. The phone reruns that day's merged statistics, so personal history
  outside Fights stays correct.
- Advance a type's checkpoint only after the server acknowledges durable
  intake. A failed upload resends the same changes.
- Known gap: HealthKit keeps deleted objects only temporarily, so a long absence
  can miss a deletion. An occasional coverage-aware reconciliation can close it
  later. An empty read never deletes server records.
- Preserve the existing finalized-Fight policy while allowing personal history
  and active Fight calculations to receive corrections.

The branch implementation uses the two new activity tables and new collector.
The currently deployed application continues to use the older tables until an
authorized migration and backend/native rollout.

## Pre-change FitFight implementation, inspected 20 Sep

These are static code findings in this checkout, not a verification of every
installed binary or a reproduction against a user's live HealthKit store.

Foreground/sign-in and manual refresh call `refreshFights`: read the local Today
value, synchronize the signed-in user's HealthKit data, then load server scores.
Overlapping calls are coalesced. Realtime Fight updates only reload the server
snapshot; showing an opponent does not query that person's Apple Health.
[Refresh coordinator](../../FitFight/AppModel.swift),
[app lifecycle](../../FitFight/FitFightApp.swift)

| Reading | Range on a current sync | Persistence |
| --- | --- | --- |
| Local Today indicator | Local midnight to now | Local status; not a replacement for server standings |
| Fight Steps | Each accepted live/awaiting-final-sync Fight start to `min(server_now, ends_at)` | Exact-window snapshot revisions; latest selected revision supplies the score |
| Fight chart checkpoints | The same Fight start to each elapsed Fight-day cutoff | Stored with the score revision; chart values are successive checkpoint differences |
| Calendar Steps | Earliest relevant Fight day to now, uploading only overlapping Fight days | `metric_days`, mirrored into `step_days` |
| Other activity days | Earlier of midnight 29 days ago or earliest relevant Fight day, through server time | Replace values by user/source/metric/day |
| Workouts | Same activity range, newest 200 returned workouts | Upsert by user and HealthKit UUID |

Sources: [Steps collector](../../FitFight/HealthKitStepAggregates.swift),
[activity collector](../../FitFight/HealthKitActivityAggregates.swift),
[server-issued windows](../../web/lib/supabase/queries/provider-uploads-supabase-query.ts),
[writer](../../web/lib/supabase/queries/healthkit-aggregates-supabase-query.ts).
The extras request validator caps activity history at 40 days; it does not support
an arbitrary historical import. [Validation](../../web/lib/types/healthkit/healthkit-aggregate.ts)

The sole current HealthKit observer watches Steps. A delivered notification runs
the same backend synchronization, including available extras. There is no
independent workout observer or anchored incremental reader. Background work has
a 25-second cancellation deadline, and other activity failures may be omitted or
swallowed while Steps succeed. [Sync store](../../FitFight/HealthKitStepsStore.swift),
[extras writer](../../web/lib/supabase/queries/healthkit-aggregates-supabase-query.ts)

### Concrete inconsistencies to address in the proposed pipeline

- Calendar Steps are finalized when saved as a past day. Subsequent writes cannot
  change a finalized row, both in the upsert and a database trigger. Meanwhile a
  live Fight total can still change. Profile statistics read these calendar rows.
  The current Fight chart already uses checkpoints from the score revision;
  it no longer derives its chart from the separate calendar buckets.
  [Freeze rules](../../supabase/migrations/20260911160000_freeze_fight_and_civil_days.sql),
  [profile reads](../../web/lib/supabase/queries/shared-profiles-supabase-query.ts),
  [Fight snapshot](../../web/lib/supabase/queries/fight-snapshot-supabase-query.ts),
  [chart construction](../../FitFight/AppModel.swift)
- Workout cleanup treats an ID absent from the uploaded list as deleted within
  the preceding 40 days. The usual collection window is about 30 days and the
  query is capped at 200 results. Missing from that list is not proof that Apple
  deleted a workout. Replace this inference with explicit deletion events and
  coverage-aware reconciliation. This is a code-path finding, not evidence that
  a particular user's workout was removed.
- Activity-day upserts only touch supplied rows. An omitted day/metric does not
  retract an old value. Empty/denied/incomplete reads cannot safely mean zero.

Personal activity history should remain correctable. Keep finalized Fight results
frozen under the existing competition policy, separately from historical-data
corrections. Any schema/trigger change must preserve supported clients through
the staged rollout in [shipping](../shipping.md#api-compatibility-for-every-change).

## Historical activity can change

There is no documented "older than yesterday is final" guarantee in the reviewed
Apple contracts. HealthKit samples themselves are immutable, but the set of
samples can change: historical samples can arrive later, a user can add data with
an activity date, and records can be deleted or replaced. Apple describes edits
as deleting and adding a sample. That can change totals for an earlier day without
mutating the original sample. A last-24-hours activity filter is consequently not
a complete historical change detector. [HKSample][sample], [Apple's Health data
guide][health-guide], [WWDC20 synchronization][wwdc]

This establishes that historical HealthKit results can change. It does not claim
Apple routinely recalculates every old activity, establish a maximum delay, or
prove that any particular FitFight discrepancy came from Apple. Freezing a Fight
after a chosen deadline is a FitFight scoring policy, not an Apple finality rule.

## What an incremental refresh should read

An anchored query separates **when the activity happened** from **when the local
HealthKit store changed**. Its anchor identifies the last returned position in
the store's changes. Passing `nil` initially returns matching existing samples
and recently deleted objects. Reusing the returned anchor asks for subsequent
saved or deleted objects. A newly saved sample can describe an older activity
interval. The predicate still filters the results, so an anchor does not recover
history excluded by the query. [Anchored query][anchored], [initializer][initializer]

Proposed refresh contract:

1. Bootstrap each supported sample type across the explicitly retained and
   authorized history. Page through the initial results and subsequent deltas
   until caught up. A fixed result cap must not silently mean "complete."
2. Keep a separate anchor for each account/environment, local HealthKit store
   generation, sample type, and query configuration. Treat anchors as opaque local
   cursors, not timestamps or a global server ordering. Rebootstrap when the
   device/store or query scope changes; do not reuse a moving "since last sync"
   activity predicate and assume earlier changes remain covered.
3. Upload added records and explicit deletion identifiers. Keep sample activity
   dates, collection time, and server receipt/revision separate. A deleted
   object's collection time is not its original activity or deletion time.
4. Commit a page's next anchor only after the server durably acknowledges its
   idempotent ingestion and required invalidation work. Retain the page for replay
   until then. A lost response must permit the exact same upload again. Do not
   save an anchor merely because HealthKit returned it or an HTTP request began.
5. Refresh on foreground/manual entry and use observers for background changes
   for every type whose freshness matters. An observer reports that something
   changed; an anchored or statistics query must retrieve the data. For iOS Steps,
   background delivery is at most hourly, not a promise of an hourly server sync.
   Finish the observer's completion protocol after processing the delivery.

Items 1-4 are proposed application guarantees built on the anchored-query
contract; Apple does not supply server acknowledgements or promise a portable
cross-device cursor. Item 5 follows [observer queries][observer] and
[background delivery][background].

## Deletions and reconciliation

`HKDeletedObject` exposes the deleted sample UUID, not its original start/end
interval. Its metadata retains only the sync identifier and sync version. Apple
explicitly says deleted objects are temporary and may be removed at any time. It
recommends observer queries with background delivery to receive deletion
notifications promptly. An anchor is therefore not an indefinite deletion
archive. [Deleted object][deleted], [deleted UUID][deleted-uuid],
[deleted metadata][deleted-metadata]

Proposed handling: preserve a UUID-to-type-and-interval index before applying a
deletion, then invalidate all affected metric windows. If the interval is unknown,
refresh the relevant retained projections instead of assuming the deletion is
irrelevant. Reinstallation, lost cursors, long absences, and changed collection
scope need reconciliation against currently readable records/statistics. An
initial reread alone cannot identify every old deletion on the server.

Reconciliation must distinguish explicit tombstones from missing observations.
HealthKit hides denied read permission, and current documentation also describes
limited historical access. An empty query or a record missing on a second device
does not by itself prove deletion or zero activity. Do not bulk-delete server
records based on that absence. Where access prevents reconciliation, preserve an
explicit unknown/stale state instead of claiming the historical copy is exact.
[Authorization][authorization]

## Repeated workout uploads and multiple devices

Reading or uploading the same workout again does not inherently create a new
workout. Whether the server duplicates it depends on its write contract. Proposed
record identity is the authenticated user, provider, and HealthKit object UUID,
with an upsert/unique constraint and replay-safe deletion handling. Repeated
delivery of the same UUID should leave one record. Track the uploading device
separately from record identity, so two devices reporting that UUID do not create
two rows. A tombstone must prevent a delayed replay of that UUID from resurrecting
the deleted record. [Object UUID][uuid], [deleted UUID][deleted-uuid]

This does not deduplicate two different HealthKit objects that represent the same
real-world workout. Different apps can create distinct records. Source identity
and available sync/external identifiers can support a separately specified
semantic deduplication policy; matching only date and duration risks discarding
legitimate records. Apple's external UUID is separate from the HealthKit UUID
and can identify copies created across devices. [External UUID][external-uuid]

Apple's sync identifier/version metadata prevents duplicate writes and replaces
older versions **inside HealthKit when a writer supplies those keys**. It is not
automatic deduplication of FitFight uploads or a guarantee that every third-party
record contains a shared identifier. [Sync identifier][sync-id], [WWDC20][wwdc]

## Proposed records-to-metrics pipeline

For workout records and received merged totals, the prepared pipeline uses this flow:

```text
HealthKit bootstrap/delta
    -> durable, idempotent records plus tombstones
    -> affected intervals and metric dependencies
    -> versioned metric projections
    -> one server revision for score, chart, and standings
```

Store only fields required by the collection purpose: identity, type, interval,
value/unit or workout fields, relevant source provenance, and supported metadata.
Record the batch identity and sync coverage separately. Apply a batch and its
pending metric work durably together, then acknowledge it. Recompute affected
projections from the retained canonical data, rather than adding each upload's
value to an existing total. Publish a complete projection revision so a reader
cannot combine a new score with an old chart. Account for every window a sample
overlaps and, for cumulative charts, later checkpoints that depend on it.

**Steps still need Apple's merged statistics.** Apple documents that statistics
queries merge data sources before calculating results. Its synchronization talk
specifically demonstrates using anchored changes to select affected days, then
rerunning statistics and sending those results to the server. Raw sample sums,
or sums of independently calculated source totals, do not establish equivalence
to Apple's merged total. HealthKit can also condense/coalesce Steps samples.
[Statistics][statistics], [WWDC20][wwdc], [Step count][steps]

For FitFight Steps, the proposed pipeline therefore also receives authoritative
merged statistics for affected Fight windows and cumulative checkpoints. Local quantity samples provide change detection without leaving the phone
or becoming a competing score. Keep a score and its chart on the same cutoff/revision; do not assume that
independently rounded daily totals exactly sum to a separately queried total.

A periodic or recovery statistics reread remains useful. Users can change Health
source priority, but the reviewed sources do not promise that every such change
produces a sample add/delete delta. Nor do they expose a complete server-side
algorithm for reproducing Apple's merge. A finite refresh/retention horizon must
be an explicit product limit, not a claim of historical immutability.
[Health source priority][health-guide], [Statistics][statistics]

## Verification boundary

Official Apple documentation and the WWDC20 transcript were checked on
20 Sep 2026. No physical-device behavior, live user data, backend implementation,
or cloud deployment was tested for this note. Before implementation, verify
historical insertion, replacement/deletion, offline replay, lost acknowledgement,
multiple devices, cursor reset, restricted access, pagination, source overlap,
midnight/DST boundaries, and chart/score agreement. Background delivery requires
a physical device; Apple does not support testing it in the Simulator.
[Background delivery][background]

[sample]: https://developer.apple.com/documentation/healthkit/hksample
[health-guide]: https://support.apple.com/en-us/108779
[wwdc]: https://developer.apple.com/videos/play/wwdc2020/10184/
[anchored]: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
[initializer]: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery/init(type:predicate:anchor:limit:resultshandler:)
[observer]: https://developer.apple.com/documentation/healthkit/executing-observer-queries
[background]: https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
[deleted]: https://developer.apple.com/documentation/healthkit/hkdeletedobject
[deleted-uuid]: https://developer.apple.com/documentation/healthkit/hkdeletedobject/uuid
[deleted-metadata]: https://developer.apple.com/documentation/healthkit/hkdeletedobject/metadata
[authorization]: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
[uuid]: https://developer.apple.com/documentation/healthkit/hkobject/uuid
[external-uuid]: https://developer.apple.com/documentation/healthkit/hkmetadatakeyexternaluuid
[sync-id]: https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
[statistics]: https://developer.apple.com/documentation/healthkit/hkstatistics
[steps]: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount
