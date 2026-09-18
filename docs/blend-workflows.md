# Blend workflow requests

Backend and native generation prepared 18 Sep 2026. Disabled by default, not
deployed. Marc's follow-up also authorizes the generation screen, phone recovery,
image saving and companion assignment. Cloud database and native checks have passed; the exact run links are in
status.md. Deployment, configuration and a real staging generation are still
required before this is described as usable on staging.
Existing OpenRouter recap behavior is unchanged.

Blend owns execution, models, prompts, monetary costs and detailed workflow traces.
FitFight owns authenticated admission, generation credits, safe request history and
reconciliation. The three adapters are Avatar, Five Fitness Levels and Group Photo.
They call `https://www.tryblend.ai/api/v1`; the local Blend development endpoint is
never a FitFight deployment setting. Styles and reference images stay inside Blend.

## App contract

| Endpoint | Contract |
| --- | --- |
| `POST /api/v1/ai/runs` | Start or recover an owned Avatar, Fitness or Group Photo action using a UUID `Idempotency-Key` |
| `GET /api/v1/ai/runs/{request_id}` | Read an owned action; shared leases coalesce status checks |
| `GET /api/v1/ai/allowance` | Read `available`, `reserved`, `avatar_price`, and nullable `fitness_price`/`group_photo_price` |
| `GET /api/v1/ai/library` | Read complete saved image sets owned by the account, with refreshed signed media URLs |
| `POST /api/v1/ai/runs/{request_id}/images` | Atomically attach committed owned profile media to a completed generation; no generation or credit charge |

All require the normal Bearer token and app headers. Unknown and other users'
request IDs return the same 404. New routes preserve `/api/v1`; existing endpoints,
legacy fixtures and shared error fields keep their contracts.

```json
{
    "workflow": "avatar",
    "parameters": { "description": "A fox wearing glasses" }
}
```

```json
{
    "request_id": "22222222-2222-4222-8222-222222222222",
    "workflow": "avatar",
    "status": "pending",
    "poll_after_seconds": 3
}
```

For `workflow: "fitness"`, parameters are `avatar_request_id` and `identity_details`.
For `workflow: "group_photo"`, parameters are `scene` and an ordered `characters`
array of `{ avatar_request_id, identity_details }` objects. The array requires two
to five distinct characters. The backend resolves completed Avatar requests or
saved Avatar library entries owned by the caller, and builds the numbered `cast_roster` in the same order as their
images. Raw URLs, Blend file IDs and other users' generations are not accepted.
Source authorization happens before credit reservation and provider submission.
An already-admitted action remains recoverable after source request cleanup.

This source policy excludes arbitrary profile media IDs and cross-user group
assembly. Group sizes above five and the 20-30-character grid remain outside the
verified scope. Unsaved requests retain their seven-day window. Saved library
entries and private media survive request pruning until account deletion; source
resolution signs their owned media again before submitting a derivative workflow.

`pending` and `running` include the minimum polling delay. `completed` carries
`data.image_url` for Avatar and Group Photo, or five named URLs in `data.resting`,
`data.soft`, `data.average`, `data.fit` and `data.strong` for Fitness. `failed`, `cancelled` and `start_unconfirmed` carry `code` and
`error`, including when HTTP status is 200. Results require one completed image on
an allowed HTTPS Blend host for each expected output. Fitness requires all five
images to validate before consuming its stored price; an incomplete bundle releases
the entire hold. Group Photo accepts one image from `output.group_photo`. Validation
proves the provider envelope and allowed URL, not visual quality or PNG transparency.
A returned URL is not a saved FitFight companion.

The Swift bridge supports `startAvatarGeneration`, `startFitnessGeneration`,
`startGroupPhotoGeneration`, `aiRequest`, `aiAllowance`, `aiLibrary` and `saveAIImages`.
AI calls send an individual trace ID. `FitFightAIError` preserves the request ID and
retry delay and supplies English/French descriptions. App receipt/display telemetry
is outside this scope.

## Native generation and durable images

You -> Make it yours -> Generate images opens the three workflows and the account
library. Each start displays its server price and requires enough available credits.
Fitness selects one saved avatar. Group Photo selects two to five in explicit cast
order and takes a scene description. These controls do not use HealthKit data.

The native app persists the exact action inputs and UUID key before submission,
then persists the request ID and each committed image upload under the account's
local key. Closing the screen stops local polling; reopening resumes the same
action. Unknown/network outcomes retain the action. Definite pre-admission
rejections or terminal results let the user start a new deliberate action. A
corrupt local action disables starts instead of risking another paid request.
Account checks prevent delayed responses from updating a different signed-in user.

Completed images pass through the existing signed upload and checksum commit flow,
preserving PNG transparency. The new library attachment requires a completed owned
request, distinct owned ready photo media, and exactly the workflow's expected
stages. The app supplies the downloaded result images; the attachment API validates
ownership and completeness, not visual provenance. It never fetches arbitrary
client URLs or starts Blend. The first save must occur within request retention;
repeated saves of the same IDs remain idempotent after pruning. An interrupted
upload may leave an unassigned media object, handled by the existing account media
lifecycle; it cannot trigger a second generation charge.

Avatar and individual Fitness images can be chosen as the custom companion with
one existing profile update. The chosen image appears on You and existing avatar
surfaces. Fitness images are selectable poses; automatic switching by Steps is
not added. Group photos stay in the private library; fight assignment and
cross-user casts need their own product contract. Stock selection and saved text
descriptions remain available. A 1.1.1 release note and English/French copy were added.

## Credits and balance events

Avatar admission stores a fixed price of **one credit**. Fitness and Group Photo
require explicit positive `BLEND_FITNESS_CREDIT_PRICE` and
`BLEND_GROUP_PHOTO_CREDIT_PRICE` values before new admission. Neither gets an
invented default. The selected workflow price is stored once at admission and is
consumed only for a complete validated result. This is per-workflow settlement,
not a partial charge for each image. New accounts have zero
credits until an explicit grant. There is no starter grant, replenishment, expiry,
purchase, subscription or payment integration. Attempt limits remain independent
of credits. Returning a user credit does not reverse a provider charge.

| Transition | Available change | Reserved change | When it happens |
| --- | --- | --- | --- |
| Grant | +quantity | 0 | Authorized operator action |
| Reserve | -stored price | +stored price | In the same transaction as admission |
| Consume | 0 | -stored price | Validated image is recorded as completed |
| Release | +stored price | -stored price | Confirmed rejection, failure, cancellation or invalid terminal output |
| Adjustment | Signed quantity | 0 | Authorized compensation referencing an original event |

A hold moves allowance into reserve. It is not charged again at completion. A lost
acknowledgement or uncertain status keeps the hold. Duplicate submissions, status
reads and reopening results create no extra accounting event. The original action,
workflow version and stored price win across retries and configuration changes.

`private.ai_credit_balances` stores current available/reserved amounts and a
per-user sequence. `private.ai_balance_events` records every change with:

- Event ID, user, sequence and database timestamp.
- Kind, bounded reason code, server process or authenticated operator ID.
- Unique operation key, request ID and admission action key where applicable.
- Quantity, plus before/change/after for both available and reserved amounts.
- Original event ID for compensating adjustments.

Transactions lock the balance and commit the event, balance and request transition
together. Constraints enforce nonnegative balances, event arithmetic and unique
reservation/settlement operations. Private integrity triggers reject history
updates/deletes and verify the zero origin, sequence chain and current balance at
commit. These triggers enforce storage invariants only; admission and accounting
policy remain TypeScript. No app-facing Postgres RPC is used.

Credit history lasts for the account's lifetime, following the existing canonical
history policy in `system-design.md`. Seven-day terminal request pruning never
deletes its balance events. Retained action keys also prevent replay of pruned
paid actions: the old key returns `ai_request_expired`. An intentionally new action
needs a new key. Account deletion removes requests, caller windows, balance,
events and user-linked HTTP logs through the existing profile cascade. Shared
provider spending counters remain. There is no separate monetary ledger or new
account-retention exception.

## Admission and recovery

Per user: three starts per rolling minute, twenty per UTC day, one unresolved
request and sixty start/status calls per fixed minute. Explicit shared daily,
concurrent and HTTP-request limits also apply. Starts and reads both count toward
the shared Blend request cap and honor observed remaining/reset/cooldown headers.
Attempt counters are conservative and are not refunded after provider failure.
They cap attempts, not monetary spending.

The backend looks up the action before checking whether new starts are enabled or
configured. Recovery still works with `BLEND_ENABLED=false` or removed start
configuration. New reservations and provider submissions remain blocked. Reusing a
key with changed input is a conflict. A different action while one is unresolved
returns `ai_in_progress` with the owned request ID.

Requests use a thirty-second start lease and fifteen-second poll leases. Only the
current lease can record a result. Submission intent is recorded immediately
before the paid POST, without holding a database transaction open during HTTP.
Lease expiry never authorizes another POST. A late acknowledgement can attach its
run ID while the original lease token remains. Unknown starts keep both their
credit hold and unresolved-capacity slot until reconciled.

## Durable timing and bounded diagnostics

Requests store creation, admission, submission intent, acknowledgement, terminal
observation and credit settlement timestamps. `provider_completed_at` separately
records Blend's optional `completed_at`; it is never filled from server observation
time. Requests retain workflow/version, Blend run identity, normalized state,
safe failure code, source request IDs, selected price and credit state. Legacy rows admitted before
this migration retain price zero/state `none` and unknown milestone values rather
than fabricated history.

Each AI HTTP call uses `X-FitFight-Trace-ID`, returned with `Server-Timing`.
`private.ai_http_logs` links app, backend/operator/reconciler and Blend calls using
trace/request/run IDs. It records actual HTTP status where available, elapsed
milliseconds, safe upstream status/code, prepared response state and whether an
action was submitted, recovered, observed or rejected. Terminal HTTP 200 failures
are recorded too. No credentials, raw descriptions, request/response bodies, image
URLs or model traces have log fields.

Logs are limited to nine summaries per invocation, seven days and 100,000 rows per
environment. Insertion and the scheduled reconciler enforce retention. Logging
failure emits only an operation/trace marker and does not change an already saved
result. Existing shared 5xx diagnostics retain their existing behavior, now with
safe AI identifiers. Platform console retention is separate from the private HTTP
log retention. A prepared response does not prove that the phone received it.

## Reconciliation and operator procedure

`GET /api/internal/ai/reconcile` is configured in `web/vercel.json` daily at 03:15 UTC as a production backup,
authenticated with `CRON_SECRET` (or the existing `FITFIGHT_CRON_SECRET` alias).
It selects at most four due known runs and uses the same status decoder, shared
provider limits, leases and atomic settlement as phone polling. It bypasses only
the user's caller counter. Work stops at the bounded invocation deadline or shared
cooldown. Runs are selected by oldest due time. Concurrent cron/phone invocations
cannot settle twice. Configure and verify a frequent hosted scheduler for each
environment, including staging, before enabling starts. The repository documents
Supabase Cron for staging scheduled work. Its secret/configuration is not available
to this workspace. [Vercel Hobby permits daily cron jobs](https://vercel.com/docs/cron-jobs/usage-and-pricing),
and [Vercel cron targets production deployments](https://vercel.com/docs/cron-jobs),
so a minute expression in vercel.json neither proves staging scheduling nor fits the
documented plan. The daily backup alone is not the required staging scheduler.

New-start disabling does not disable reconciliation. Keep the key and shared
provider limits present while known work remains. Status reads use the saved
workflow/version and price, so removing a current publication/price setting does
not strand admitted work. Expired starts
are marked unconfirmed, never inferred to have failed. Recovery never uses time
alone as evidence for a credit return or paid replay.

The operator endpoints use a verified user Bearer token whose Auth UUID matches
`FITFIGHT_ADMIN_USER_ID`. They do not trust editable user metadata, client actors,
cron credentials or service-role client access. There is no operator UI.

To grant credits, call `POST /api/internal/ai/credits` with:

```json
{
    "kind": "grant",
    "user_id": "11111111-1111-4111-8111-111111111111",
    "operation_key": "33333333-3333-4333-8333-333333333333",
    "quantity": 3,
    "reason": "explicit_grant"
}
```

This is an example operator action, not an automatic allowance. Reuse its operation
key after a lost response. The response identifies the original event and sequence.
For a correction, use `kind: "adjustment"`, a nonzero signed `change`,
`compensates_event_id`, reason and a new operation key. Reserved credits are changed
only through the associated request lifecycle. Never edit historical events.

For an unknown start:

1. Locate its request, submission time, workflow/version and correlated HTTP logs.
   Check Blend run history or provider support evidence, including any late run ID
   in the acknowledgement-persistence failure diagnostics. Ensure the original
   server invocation has ended before deciding that no execution was accepted.
2. If a run is found, verify it belongs to this request and exact saved publication.
   Call `POST /api/internal/ai/requests/{request_id}/recover` with
   `action: "attach_run"`, `run_id`, a UUID `operation_key` and an `evidence`
   reference such as `blend-history:run-42`. This retains the hold and queues a
   normal bounded status read; it does not submit work or accept an unvalidated
   output. One run cannot be attached to multiple retained requests.
3. Only with reliable evidence that nothing was accepted, use the same endpoint
   with `action: "confirm_not_accepted"`, a UUID operation key and a provider
   evidence reference such as `blend-support:case-42`. It records a failed request
   and releases the hold atomically. Elapsed time, a timeout or an ambiguous 404 is
   not that evidence. If uncertain, leave the hold untouched and investigate.
4. Retry an operator decision with the exact original key/body. Conflicting
   decisions are rejected. Stale server leases cannot overwrite the decision.

Evidence values are bounded identifiers, not copied prompts, provider bodies or
support conversations. Do not put tokens in shell history or documentation.

## Configuration and rollout

Apply the three private migrations through the authorized pipeline:

1. `20260917003356_blend_workflow_requests.sql`
2. `20260918142724_blend_credit_history.sql`
3. `20260918154236_ai_companion_library.sql`

Then deploy compatible backend code with starts disabled, configure and verify the
scheduler, perform the required cloud checks, authorize explicit grants and verify
one staging generation before activation. This foundation has never been deployed;
if an earlier request-only backend exists in an environment, keep it disabled and
drain old instances before allowing any credit-bearing request. That older writer
cannot settle the new credit constraint. Distribute the native UI only after the staging backend and image library are ready.

| Variable | Requirement |
| --- | --- |
| `BLEND_ENABLED` | Defaults to `false`; enables new starts only |
| `BLEND_API_KEY` | Deployment-only key; verify access and provider limits |
| `BLEND_AVATAR_WORKFLOW_ID` | Published workflow ID |
| `BLEND_AVATAR_VERSION_ID` | Pinned immutable Avatar version |
| `BLEND_FITNESS_WORKFLOW_ID`, `BLEND_FITNESS_VERSION_ID` | Published Fitness ID and pinned version |
| `BLEND_GROUP_PHOTO_WORKFLOW_ID`, `BLEND_GROUP_PHOTO_VERSION_ID` | Published Group Photo ID and pinned version |
| `BLEND_FITNESS_CREDIT_PRICE`, `BLEND_GROUP_PHOTO_CREDIT_PRICE` | Required explicit positive prices for these new workflows |
| `BLEND_GLOBAL_DAILY_STARTS` | Required positive shared daily cap |
| `BLEND_GLOBAL_CONCURRENT_RUNS` | Required positive unresolved-capacity cap |
| `BLEND_REQUESTS_PER_MINUTE` | Required positive shared start/read HTTP cap |
| `FITFIGHT_ADMIN_USER_ID` | Existing environment-owned operator Auth UUID |
| `CRON_SECRET` | Authenticates the hosted reconciler |

The three limits have no invented defaults. Choose them from the actual deployment
key's limits and allowed spending. A start cap is not a guaranteed monetary budget
without a verified maximum workflow cost or provider-enforced spending cap. Initial
grants and provider spending policy still require an explicit decision before use.

Read-only publication inspection on 18 Sep confirmed zero validation errors and
these current versions. The safe identifiers are included in `.env.example`;
`BLEND_ENABLED` remains false and both new prices remain unset.

| Workflow | Published ID | Pinned version | Provider input labels | Output labels |
| --- | --- | --- | --- | --- |
| Avatar | `4f885bfb-d387-4f3c-be50-1950bb0e44c3` | `738baa52-36f3-419b-a920-58627e01f045` | `describe_your_animal` | `avatar` |
| Five Fitness Levels | `fa770c5b-25ba-46cc-a758-a08aeebc1c92` | `8f2c594c-01b5-432b-a047-af75181ffde7` | `character_portrait`, `identity_details` | `resting`, `soft`, `average`, `fit`, `strong` |
| Group Photo | `f740d71e-06fe-41d4-a92d-a85c90abd3f9` | `2d6e0596-14c5-4ba2-948f-642bae407815` | `character_portraits`, `scene`, `cast_roster` | `group_photo` |

The older Avatar version `bbf425cb-1c8a-4dfa-9f0d-637f22e8f4e1` retains its original
`variable:prompt:user_request` input mapping. Saved requests always use their own
version, never a newly configured pin. Both Avatar versions have the same validated
output shape. Any future shape change needs a saved-version-compatible decoder.

Existing completed runs confirmed one Avatar image, all five Fitness images and
one Group Photo image, all on `supabase.tryblend.ai`. The inspected Fitness run was
a draft run without a published-version ID. Marc reports that the successful image
runs were performed on the Blend local branch and that production authentication
and polling work. Neither those observations nor this inspection verify new
production generations with the latest published versions, the FitFight deployment
key or the enabled FitFight pipeline. No paid run was started in this task.
Provider references: [Start a response](https://docs.tryblend.ai/endpoint/start-a-response)
and [Get a run](https://docs.tryblend.ai/endpoint/get-a-run).

## Errors and verification

Existing `{ "error": "...", "code": "..." }` responses remain valid. AI failures
may add `request_id` and `retry_after_seconds`; a known delay also sets `Retry-After`.

| Code | Client behavior |
| --- | --- |
| `ai_insufficient_credits` | Explain that no available allowance remains |
| `ai_request_expired` | Old action cannot be replayed; a deliberate new action needs a new key |
| `ai_rate_limited`, `ai_daily_limit` | Respect the user limit and retry delay |
| `ai_in_progress` | Resume the existing request |
| `ai_request_conflict` | Keep the original key/input association |
| `ai_busy`, `ai_unavailable` | Respect service availability and any delay |
| `ai_status_unavailable` | Read the same request again |
| `ai_start_unconfirmed` | Preserve the action; never automatically submit again |
| `ai_failed`, `ai_cancelled`, `ai_invalid_result` | Display the terminal failure |

Unit tests cover real HTTP transport with fake responses, domain recovery,
validation, operator authorization, safe correlation and bounded reconciliation.
The cloud database suite covers concurrent last-credit requests, duplicate grants,
reservations and settlements, compensation, rollback integrity, every event chain
and stored balance, zero allowance, ownership, disabled recovery, unknown holds,
abandoned-run completion, cleanup and deletion. pgTAP checks private privileges and
RLS. Shared unchanged AI fixtures plus the new allowance fixture feed backend and
hosted Swift contract tests. Additional Fitness and Group Photo fixtures cover the
new results without replacing the old Avatar fixtures.

See `docs/status.md` for executed checks and remaining cloud/live proof. Release promotion still follows AGENTS.md: a PR requires Marc to explicitly ask
for one, and release branches require separate merge authorization. Production needs its own authorized rollout and release
manifest check; a staging result is not production readiness.
