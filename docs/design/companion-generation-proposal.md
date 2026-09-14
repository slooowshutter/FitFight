# Companion generation — Blend proposal

Date: 14 September 2026. Status: **proposal**. No Blend workflows, API routes, or schema shipped in this change.

Stages 1–2 (native stock art + Simulator preview) already exist. Stages 3–5 in [companion-implementation-plan.md](companion-implementation-plan.md) are still pending. Marc’s 14 Sep dump is in [source/companion/generation-studies/](source/companion/generation-studies/README.md).

This supersedes the old “do not introduce a generic workflow platform” note for **image generation only**. FitFight still owns identity, limits, storage, and fight rules. Blend owns the three published graphs.

---

## Direct answers

**How many images per person?** One **active companion** on the account. That companion is reused in every fight. People do not get a private drawing per fight.

**How many images per fight?** One **shared group scene** per fight ID (one round). Everyone sees the same file. Recurring next window is a new fight ID and can get its own scene.

**When does the Fights-tab animal change?** Every day, among **five stored forms** of that companion. Couch when steps are low, more in shape when steps are high. That is a **display pick**, not a daily Blend call.

**Can people remake it?** Later: three free identity tries, then pay. **Now:** one confirmed custom companion. Failed Blend runs do not count. No payments.

**The five forms?** Generate **all five once** after they tap Use this companion. “The first of the five is free” is a later price split, not a reason to store only form 1. Without the set, the daily change cannot work.

**Who calls Blend?** The TypeScript backend, with a server `bai_` key. Never iOS. Marc authors three **private** published workflows on tryblend.ai.

---

## The three pictures

```
You / picker          Fights hero (daily)           Fight detail
┌──────────┐          ┌──────────┐                  ┌─────────────────────┐
│ Identity │  once    │ Form 1–5 │  pick, no Blend  │ Group scene         │
│ sheet    │ ───────► │ stored   │  from today's    │ 1 per fight ID      │
└──────────┘          └──────────┘  steps           └─────────────────────┘
   Blend A               Blend B                         Blend C
```

| # | Surface | Blend workflow | When it runs | Stored as |
| --- | --- | --- | --- | --- |
| A | Custom companion | Identity | User asks; confirm to activate | Companion version + full-body + avatar |
| B | Same companion, five shapes | Five forms | Once after confirm, same version | Five media ids on that version |
| C | Everyone in this round | Group scene | Organizer taps when the lineup is ready | One artwork row on the fight |

Stock Fox/Raccoon stays the bundled single pose. Do **not** spend Blend credits drawing five forms for every stock pick.

Native already shows a personal hero on Fights / New / You and a scene slot on fight detail (`CompanionIntroduction`, `CompanionFightSummary`). Production still has no server companion or group-art contract.

---

## Recommended product (v1, no payments)

### Companion (account)

1. Persist **one active companion** per user (Stage 3, stock first). It replaces the avatar on You, fights, standings, Feed, comments. Profile photo stays a separate field. Handle and scores never change with the animal.
2. **Custom:** describe animal / breed / clothes → Blend A → inspect → **Use this companion**. Only a successful confirm replaces the live selection. Failure keeps the current one.
3. **Allowance now:** one confirmed custom identity. Retry is free when Blend fails, times out, or returns an unreadable image. Double-tap reuses the in-flight job.
4. After confirm, FitFight **immediately starts Blend B** with the saved identity as the character reference. Publish the five forms only when all five land. A partial set never becomes live.
5. **Remakes / three credits / pay for more:** schema can count attempts. Do not ship a shop.

### Daily form (Fights tab)

Use **today’s Apple Health merged steps** — the same number the Fights hero already shows. Fight-window totals stay on fight detail and do not drive this picture.

| Form | Picture (studies) | Today’s steps |
| --- | --- | --- |
| 1 | Couch, blanket, mug | 0–2,999 |
| 2 | Up, walking, still soft | 3,000–5,999 |
| 3 | Walking in kit | 6,000–9,999 |
| 4 | Jogging | 10,000–14,999 |
| 5 | Sprinting, more muscular | 15,000+ |

Stay on the current form until the total crosses the next band by **500**, so the hero does not flicker around 10k. Missing Health → form 1 plus the existing “unavailable / connect Health” copy. Forms never change scores.

Custom companion without a complete five-set: show the identity full-body, not a fake ladder.

### Group scene (fight)

Fights can start with the **owner alone**. Auto-generate at Slide to start would mint a solo “group.”

**Recommended trigger:** the organizer taps **Make the scene** when the lineup is ready. Snapshot **accepted** members only. Skip invited and deferred (waiting for the next round). Scoring, join, leave, Feed, and standings never wait on Blend.

After publish: **no silent remake** on join, leave, companion edit, score change, or refresh. Late joiners appear in standings only. Next recurring round = new fight ID = new optional tap.

**Cast in the drawing:** 2–4 accepted people who already have a companion. Nano Banana 2’s catalog copy is “up to 14 images: 10 objects + **4 characters**.” Fights may have ~50 members. If more than four accepted, still one picture of **organizer + three earliest accepted**, with native copy **4 of N**. Do not send 50 refs.

**Activity:** walking / Steps together. Swim, climb, and fence in the dump are composition studies, not fight types. Do not paint ranks, step counts, or the loser action into the PNG. Usernames stay native text under/around the image (the dump’s names-on-caps will fight live standings).

While pending or failed: keep the current fight layout and an honest image status. Optional free fallback: a collage of stored companion bodies. That is not the dump’s group illustration; use it when Blend is skipped or N>4 and Marc prefers “something on screen” to empty.

Account deletion removes owned companion media and **invalidates** group art that included that companion. Show no-art. Do not auto-spend another Blend run.

---

## Options (pros / cons)

### A. Identity tries

| Option | Pros | Cons |
| --- | --- | --- |
| **1 confirmed (recommended now)** | Matches “just generate one.” Cheap. Failed runs can retry. | A bad hat is stuck until remakes exist. |
| **3 confirmed tries, then lock** | Matches later credits. Lets people iterate glasses/breed. | 3× Blend per custom user. Needs a counter. Do not hide a shop behind try 4. |
| Unlimited | Good for Marc testing prompts. | Staging bill unbounded. |

Do **not** consume a try on provider 5xx, timeout, empty output, or leaving the screen while the job is still running.

### B. Five forms

| Option | Pros | Cons |
| --- | --- | --- |
| **All 5 once after confirm (recommended)** | Daily couch→muscle with **zero daily Blend**. Matches turtle/raccoon/cat/goat sheets. | Two Blend runs per custom user (A + B). |
| Only form 1 / identity pose now | Literal “generate one.” Faster Custom trial. | Fights hero cannot change. Charging for 2–5 later feels like bait. |
| Generate today’s form on demand | No unused images. | A Blend call every active morning. Slow Fights tab. No Blend webhook. **Do not.** |
| Generate form N the first time that band is hit | Spreads cost. | Inconsistent character; the 15k day is the first time you see form 5. |

### C. Daily form input

| Rule | Pros | Cons |
| --- | --- | --- |
| **Today’s steps, 3k/6k/10k/15k, ±500 (recommended)** | Same number already on Fights. Couch in the morning, muscular after a long day. | Watch catch-up can jump two forms. |
| Yesterday’s completed day | Stable all morning. | “I walked 16k and I’m still on the couch until tomorrow.” |
| 7-day average | Less ping-pong. | Opaque. A rest day does not show couch. |
| Fight rank / gap | Dramatic. | Wrong surface: the Fights hero is **you**, not a fight. Implies art is scoring. |

### D. Group timing

| Trigger | Pros | Cons |
| --- | --- | --- |
| At fight start | Zero extra tap. | Owner-alone and incomplete invites mint the wrong cast. Waste on abandoned solos. |
| Auto when accepted hits 2+ | Feels magic. | Second joiner can be deferred. Public Join can hit 2 then 30. Racey double-charge (Blend has **no idempotency key**). |
| **Organizer tap when ready (recommended)** | Intentional snapshot. Works with solo start + later accept. | Organizer may never tap; fight still works (required). |
| Daily / on every score sync | — | Cost bomb. Art would chase ranks. |
| At `ends_at` | Cast is final. | People only see it when the fight is over. |

### E. How many group images

| Option | Pros | Cons |
| --- | --- | --- |
| **1 shared image per fight ID (recommended)** | Cheap. Same picture for everyone. Recurring = new ID = optional new tap. | Late joiners omitted. 50-person fight cannot be a true group photo. |
| 1 per user per fight | Personalized. | **N Blend runs per round.** Character-ref still max ~4. |
| 1 per join event | Always current. | Regen storm. |
| Night + Day pair | Matches current opaque race/tennis files. | 2× cost. One opaque illustration already sits on both themes. |
| 0 Blend; collage of stored companions | Free, always current, any roster size. | Not the dump’s named group illustration. Keep as **fallback**. |

### F. Remakes (later)

| Asset | Now | Later |
| --- | --- | --- |
| Identity | Confirm locks. Failed job → Retry (same slot). | 3 confirmed tries, then pay. Each confirm is a **new companion version**. Old fight art keeps the versions it was minted with. |
| Five forms | Locked to that identity version. Identity remake enqueues a new 5-set; never mix two identities. | Paid remake of the set. |
| Group | No remake after publish. Failed run retries **the same job**. | Paid “update the poster,” still one published file per fight ID. |

---

## Blend: how FitFight should call it

Checked 14 Sep 2026 against Blend MCP + [docs.tryblend.ai](https://docs.tryblend.ai/). There are **no FitFight companion workflows** in Marc’s Blend account today. Existing published graphs (wardrobe, posters) are unrelated.

### Two surfaces — do not mix

| Surface | Who | Start | Files | Poll |
| --- | --- | --- | --- | --- |
| **Workflow REST API** | FitFight `web/` | `POST https://tryblend.ai/api/v1/responses` | HTTPS URLs | `GET /api/v1/runs/{runId}` every 1–3s |
| **Blend MCP** | Cursor / Marc in the editor | `run_workflow` | `ingest_media` file ids | `workflow_runs` |

MCP is for **authoring**. Production uses a `bai_` key from [tryblend.ai/settings?tab=api-keys](https://tryblend.ai/settings?tab=api-keys). Header: `Authorization: Bearer bai_...`. Key owner is billed. Never put the key in git, chat, or iOS.

Publish the three graphs **private**, with stable `apiSlug`s. Pin `versionId` in FitFight env after a quality trial.

REST has **no webhook** and **no idempotency key**. Re-POST starts a new billed run. FitFight must insert a generation row **before** calling Blend; if `blend_run_id` exists, only poll.

Outputs are Blend CDN URLs. Copy them into FitFight `user-media` before showing them to other people.

Errors to handle: `402` insufficient credits, `429` + `Retry-After`, `400` invalid inputs, `404` workflow not found / not owned.

### Model

Default image node: `google/nano-banana-2` (catalog, 14 Sep). Text + image in; up to 14 refs; **4-character** note in the file-handle description; 1K default. Pro is slower/costlier. Lite is cheaper but weaker on many refs.

Style refs from the dump should be **baked into the Blend graph** (like Marc’s other private poster workflows), not re-uploaded from the phone every run. User-specific inputs are the description and the approved identity image(s).

### Recipes for Marc’s three graphs

| Workflow | Blend recipe | Graph |
| --- | --- | --- |
| **A Identity** | `optional_reference_image_generation` | Required description → `parameter_prompt`. Optional extra photo → `parameter_images`. Result: identity image. FitFight can crop the avatar after download. |
| **B Five forms** | `batch_photo_matrix` | One Batch with **five authored rows** (couch → sprint). Prompt template `Same character as the reference, {{activity}}…` → `variable:prompt:activity`. Identity image → `parameter_images` with `mediaCardinality: together`. Result: **five items** (`item_index` 0–4). Do not add a second Batch (cartesian cost). |
| **C Group** | `media_bundle_or_explode` | Many identity images → `parameter_images` with **`together`** (one scene). `explode` would draw one scene per person — wrong. |

Do not use in-graph **Choose before run**. Identity approval lives in FitFight after A completes.

### Suggested published labels

After publish, copy the real `input_schema` from Blend into FitFight. Labels become snake_case API keys (`Reference Image` → `reference_image`). Illustrative contract:

**A — slug `fitfight-companion-identity`**

```json
{
  "animal_description": "orange tabby, red scarf, green kit",
  "images": ["https://…optional extra photo…"]
}
```

Result key: `identity_image` (one image part). Aspect **3:4** or **2:3**, size **1K**. Cream paper, moss kit, standing, painted ground, no text.

**B — slug `fitfight-companion-forms`**

```json
{
  "images": ["https://…approved identity full-body…"]
}
```

Five result items, index 0 = form 1 (couch) … 4 = form 5 (sprint). Aspect **3:2** or **16:9** strips. Same face, clothes family, accessories. No captions.

**C — slug `fitfight-fight-scene`**

```json
{
  "images": ["https://…identity url…", "https://…"],
  "scene": "walking together on a pale dirt path, 4 animals, cream paper, moss kit, no text, no numbers"
}
```

`images` length 2–4. Aspect **16:9** or **21:9** to match the fight-detail hero (native currently trims the scene to 168 points).

### FitFight secrets (server only)

```
BLEND_API_KEY
BLEND_WORKFLOW_IDENTITY=fitfight-companion-identity
BLEND_WORKFLOW_FORMS=fitfight-companion-forms
BLEND_WORKFLOW_GROUP=fitfight-fight-scene
# optional pins after the quality trial:
BLEND_VERSION_IDENTITY=
BLEND_VERSION_FORMS=
BLEND_VERSION_GROUP=
```

Marc creates the key and pastes it into Vercel (staging first). Agents do not receive it in chat.

### Call sequence

```
iOS → authenticated FitFight API
  → insert generation_attempts (client request_id, pending)
  → if blend_run_id exists: poll only
  → POST /api/v1/responses { workflowId, stream: false, inputs }
  → save run_id + published version id
  → poll GET /runs/{id} from cron / app-open drain (same pattern as notification outbox)
  → on completed: download image parts → user-media → mark ready
  → only then confirm companion / publish fight artwork
```

---

## FitFight implementation sketch (when building, not this PR)

Order still wins: **Stage 3 stock identity on the account** before any generated face is shown to someone else.

### Data

New tables (names indicative):

| Record | Contents |
| --- | --- |
| `companions` / versions | Owner, stable id, stock vs custom, species, original description, structured traits, art-direction version, identity media, avatar media, five form media, status |
| `profiles.active_companion_version_id` | Current selection. Draft does not replace until confirm |
| `generation_attempts` | Kind (`identity` \| `forms` \| `group`), owner/fight, input version map, workflow slug + version, `request_id`, `blend_run_id`, state, cost, error |
| `fight_artwork` | Fight id, published media, participant → companion-version map, attempt id, generated_at |

Companion edits produce a **new version**. A fight image keeps the versions that created it.

### Media

Today `media_purpose` is only `profile` | `fight_post`. Generated art must **not** become a Feed post or overwrite the real photo.

Compatible approach: new purposes (`companion`, `fight_artwork`) behind a **new** API contract, not by stuffing values into the existing enum that old clients decode strictly. Store media ids, not expiring URLs. Path `{owner_id}/{purpose}/{id}` in `user-media`. Visibility follows fight access / owner. `DELETE /api/v1/me` already deletes the owner’s `media_objects` and storage paths — companion files must use that ownership.

Old `GET /api/v1/me` and fight snapshot stay valid. Add **optional** `companion` on self-profile and snapshot `profiles[]`. Swift `Codable` ignores unknown keys; do not rename `avatar`.

### Jobs

No Inngest. Reuse HTTP cron + DB outbox + app-open maintenance (`close-fights`, `fights/refresh`). Add a drain that polls in-flight Blend runs. The phone never holds Blend secrets. Leaving You must not lose a running job.

Dedupe: one in-flight identity/forms job per `(user, companion version)`; one group job per `fight_id`. Treat unknown-in-flight as **do not resubmit**.

### Native

- You: Custom + description + generate / retry / use this companion. Loading and failure. Keep current while pending.
- Fights: hero uses today’s steps → form 1–5 when the set exists.
- Fight detail: scene slot shows published art, pending, failed, or empty. Organizer CTA **Make the scene**. Standings always below as now.
- English + French. Changelog row only when users can see it on a build.

### Cost shape (order of magnitude)

Custom user ≈ **2 Blend runs** (identity + five-form batch). Group ≈ **1 run per round the organizer actually taps**. Daily Fights-tab change = **0 runs**. Do not pre-generate 12 stock × 5 forms (60 runs) on every picker.

---

## Build now vs later

**Now (after Marc answers the questions below, still no payments)**

1. Stage 3: persist stock companion; project it on snapshots and Feed; keep profile photo; old fixtures still decode.
2. Generation-attempt table + Blend poll worker + companion/fight-art storage.
3. Custom identity: one confirm, workflow A.
4. Five-form job once after confirm; store all five.
5. Fights-tab form pick from today’s steps.
6. Group: organizer tap, 1 image/fight ID, 2–4 in frame, fallback empty/collage, standings always usable.

**Not now:** payments, credit packs, daily Blend, per-user fight art, auto regen on join, 5–50 character Blend, swim/climb/fence as fight types, Night/Day double generation, Health in Blend, stock 5-packs, video, live-effort artwork.

---

## Marc — one line each

1. After **Use this companion**, run the five-form workflow immediately (second Blend run) so the Fights hero can change, or stay on the single identity pose until you say otherwise?
2. Stock animals: **one bundled pose forever**, or also generate five forms (Blend cost on every Fox pick)?
3. Group art: **organizer tap** (recommended) or auto when the **2nd accepted** member exists?
4. Fights with **5–50** accepted: skip Blend and show avatars, or one **4-of-N** picture (organizer + three earliest accepted)?
5. Recurring next round: **new tap** for a new fight ID, or reuse last round’s PNG even if someone left/joined?
6. Identity remakes, when you want them: **3 confirmed tries then lock**, or lock after the first confirm until payments exist?
7. Daily form input: **today’s steps with 3k/6k/10k/15k** (recommended), yesterday’s day, or 7-day average?
8. Group recipe: always **walking / Steps together**, or should the organizer pick swim / trail / climb / fence from the dump (still not live Health)?

Reply with 1–8. Next chat can author the three Blend graphs to this contract and then implement Stage 3 + the Blend client. Do not implement generation until those answers land — different answers produce different jobs and bills.
