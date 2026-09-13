# Companion implementation plan

Date: 13 September 2026. Status: Stages 1–2 implemented and checked in Simulator; ready for Marc's visual review. See the [implementation handoff](companion-simulator-handoff.md). Stages 3–5 await the native review gate below.

## Outcome and order

Marc has selected the Companion visual direction. The first deliverable is the real SwiftUI app running in his local iOS Simulator with the approved layout and fixed animal artwork. After that visual review, add account-backed companion selection, custom character generation, and one generated group illustration per fight.

Marc subsequently requested implementation of this plan. His explicit request to test in his local iOS Simulator supersedes the repository's cloud-only default for this design-validation work. PRs, merges, deployment, and paid generation remain subject to the review and shipping rules below.

The stages below are implementation checkpoints. Complete and review the native Simulator milestone before starting the generation stages.

## References and current implementation

- Selected layout: [Companion app proposal](source/kit/companion-app-proposal.html), also available as a [private interactive preview](https://fitfight-five-designs.marc719509.chatgpt.site/companion-app-proposal.html).
- Visual foundations: [tokens.json](source/tokens.json) and [the native design kit](source/kit/FitFight%20Design%20System.dc.html). Keep Nunito, Night/Day, semantic Moss/Ember/Gold, 22-point cards, hairline borders, and the top version line.
- Product behavior: [current status](../status.md). The HTML contains sample data and simplified interactions; the existing native/backend behavior remains authoritative.
- Architecture: [system design](../system-design.md) and [backend boundary](../backend.md). SwiftUI calls the TypeScript backend for application data; Supabase remains the Auth provider and backend persistence.

The native app already has Fights, New, Feed, You, create/join/share, recurring rounds, standings, chart data, profile photos, and media posts. Modify those screens rather than creating a second application or embedding the HTML.

The existing `ScreenshotExport`, `AppModel` fixtures, and screenshot-only `SessionStore` initializer provide reusable preview data. They do not currently constitute a complete interactive, signed-in Simulator demo: ordinary launch still reaches authentication, Feed loads through the API, and several fixture fight IDs are not UUIDs.

Local readiness was checked without building or launching the app: Xcode is selected at `/Applications/Xcode-beta.app/Contents/Developer`; iPhone 17 and iPhone 17 Pro simulators are available on iOS 26.5 and iOS 27.0. Recheck the destination when implementation begins; prefer the installed iOS 26.5 runtime for the first review.

## Stage 1 — Preserve the chosen design and prepare assets

1. Save clean reference screenshots under `docs/design/source/companion/screenshots/`, with a short README identifying them as the selected Companion layout. Capture Fights, a two-person fight, a group fight, New, creation review, Feed, You, and the companion picker in both themes. Include empty and loading states during native implementation. Capture at 393 × 852 points and distinguish prototype screenshots from later native captures.
2. Retain the self-contained HTML as the tappable reference. Update the design source index to link the selected layout and identify the current four tabs correctly. The token palette remains the foundation.
3. Save the existing source artwork and a small asset manifest under `docs/design/source/companion/`. Record stable animal IDs, source image, intended crop, pixel dimensions, transparency, and intended surface. Preserve the originals so future work does not depend on temporary generation files or embedded HTML alone.
4. Prepare individual native image assets for the approved stock animals, including full-body and small-avatar framing. Inspect actual alpha channels and all edges; prevent neighboring characters from the prototype's sprite atlas appearing in a crop.
5. Preserve the existing race and tennis group compositions. The current group images are opaque variants matched to Night/Day surfaces, while the solo atlas has genuine transparency. Reuse these known assets for the first review and defer the lighting pass. Never label an opaque image as a transparent cutout.

**Complete when:** references are reproducible from the repo, animal assets render without clipping or checkerboards, and both group scenes fit the phone while retaining the full cast and ground.

## Stage 2 — Implement the native Simulator milestone

Start from `develop` in an appropriate feature checkout, preserving the current workspace branch and unrelated untracked work. Carry the selected prototype and assets into that checkout. Do not rename the current branch or sweep other design/research files into this change.

### Screen changes

| Surface | Implementation | Existing behavior to retain |
| --- | --- | --- |
| App frame | Match the selected spacing, tab treatment, surfaces, and type using native components. | Fights / New / Feed / You, top version line, system safe areas, navigation, and sheets. |
| Fights | Add the personal companion hero and today's Steps above the invitations and compact fight rows. | Real invite counts, relative score gaps, remaining time, refresh progress, cached data, and finished results. |
| Fight detail | Add the companion/group illustration area and the selected score/standings layout. | Stats by default; History only when previous rounds exist; Feed access, invitations, join choices, ties, deferred members, pending settlement, final results, sharing, and leaving. |
| New | Apply the Companion introduction and the approved form styling to the existing flow. | Steps only; 3/7/14/30 days; public/private; optional exact usernames; repeat; title/action; review; Slide to start; code lookup and public join list. |
| Feed | Apply the selected typography, spacing, and card treatment. | Actual posts, photos/video, Main/fight destinations, tags, emoji reactions, nested comments, deletion, reporting, hiding, and pagination. |
| You | Add the companion display and stock-animal picker. | Profile identity and photo controls, Apple Health, Bugs & requests, settings, referrals, Versions, Night/Day, account deletion, and sign-out. |

The hero's daily total comes from the existing HealthKit store; fight totals continue to use their exact fight window. Missing daily data must read as unavailable/connection-needed, never as an invented total. Copy and expressions must agree with actual standings; do not port the HTML's fixed `#1`, “Synced just now,” or winning text into live data.

Use small native companion/scene views where multiple screens share the same rendering. Fit the animal and its ground into the layout, support a subtle tap response, and respect Reduce Motion. Keep business operations in their current stores/API paths. Preserve English and French localization and larger text sizes.

### Make the Simulator useful immediately

Prepare an explicit Debug + Simulator-only Companion preview launch configuration, reusing the existing fixture mechanisms and the same production SwiftUI views. This gives Marc populated screens without depending on Apple sign-in or walking data for the visual review.

- Seed consistent people, animals, valid fixture UUIDs, group/duel fights, one invitation, recurring history, and sample Feed posts.
- Allow navigation, theme switching, stock-animal selection, form editing, and opening sheets. Keep preview selection local to the preview session.
- Mark preview data clearly. At submit boundaries, explain that this mode does not create a real fight, send a post, delete an account, or sync HealthKit. Do not build a second mock backend to simulate the whole product.
- Keep the preview mode out of Release builds and prevent its launch path from starting Auth, backend refresh, upload, push registration, or HealthKit work. Reuse the existing screenshot setup where it fits; audit root tasks as well as individual views.
- Keep the ordinary signed-in app path connected to the existing staging API. Exercise real write operations separately with an authorized staging session; credentials must never be committed or printed.

Until Stage 3, the animal picker is a local design-preview control. Do not imply that another user's animal selection is already stored or synchronized. Preserve existing profile photos/initials in real account data. The supplied four-animal scenes illustrate the demo cast; do not represent that fixed cast as the actual roster of every live fight, and do not create fake Feed posts from the tennis illustration.

### Expected files

- Screens: `FitFight/ContentView.swift`, `FightsListView.swift`, `FightDetailView.swift`, `NewFightView.swift`, `FeedView.swift`, and `YouView.swift`.
- Shared native rendering: a small Companion view file if needed, plus targeted changes to `FitFight/DesignSystem/` components. Keep both token JSON files byte-for-byte identical.
- Artwork: named imagesets in `FitFight/Assets.xcassets/`; no base64 HTML or web view inside the app.
- Preview setup: `FitFight/FitFightApp.swift`, `AppModel.swift`, `SessionStore.swift`, `ScreenshotExport.swift`, the relevant Feed fixture seam, and an explicit Simulator launch configuration. Scope changes to the preview entry point and rendering needs.
- Packaging: register every new Swift file in `FitFight.xcodeproj/project.pbxproj`; use the existing asset catalog resource entry.
- User-facing strings: `FitFight/Localizable.xcstrings`. Add the release note when preparing the native change for users, retaining marketing version `1.0.0`.

### Simulator checkpoint

Build the actual `FitFight` scheme for an installed iPhone Simulator using a workspace-local DerivedData directory and simulator signing settings. Install and launch that build, then leave Simulator open for Marc to tap through it. Record the exact reproducible launch command/configuration in the implementation handoff. No PR or TestFlight build is needed for this local review.

**Complete when:** Marc can navigate the real SwiftUI app in Simulator, compare the main screens against the selected HTML in both themes, change the preview animal, and see group artwork at phone size. Preview-only behavior is clearly identified and cannot run in Release.

## Stage 3 — Save companion identity across accounts

After the Simulator design is accepted, add one account-backed active companion per user. Start with the existing stock animals, so identity and synchronization work before paid image generation is involved.

Keep companions separate from the existing uploaded profile-photo field. Add explicit compatible companion fields to the self-profile and the other-user projections needed by fight snapshots and Feed. Older clients must keep decoding their existing profile and media contracts.

Proposed domain records:

| Record | Persisted information |
| --- | --- |
| Companion version | Owner, stable companion ID/version, stock/custom source, species, original user description, structured traits, clothing/accessories, short user-visible caption, FitFight art-direction version, and approved reference asset(s). |
| Active selection | The companion version currently chosen by the owner. A new draft does not replace the current selection until approved. |
| Generation attempt | Operation kind, owner/fight, exact input versions and references, resolved prompt, provider/model, provider request ID, state, output asset, and recorded usage/cost when supplied. |
| Fight artwork | Fight ID for one round, one published image, participant-to-companion-version mapping, generation attempt, and generation timestamp. |

Companion edits produce a new version. A fight's saved image continues to point to the versions that created it; changing glasses next week must not rewrite an old scene. Store original free text alongside structured fields so interpretation does not erase what the user asked for. Keep free-form descriptions and complete generation prompts owner/server-private; other members receive the display identity and authorized artwork they need.

Use additive migrations and the existing authenticated backend. New schemas/types belong in `web/lib/types/companions/`; database queries belong in `web/lib/supabase/queries/`; business operations remain TypeScript. Extend shared contract fixtures and the native decoders. Do not add app-facing database RPCs or direct Swift database queries.

**Complete when:** a stock-animal selection survives relaunch and another session, the same chosen animal appears consistently for its owner and other authorized fight members, profile-photo behavior still works, and old API fixtures still decode.

## Stage 4 — Custom companions and the FitFight prompt

Author a versioned FitFight art-direction recipe from the selected artwork. The recipe fixes illustration technique, proportions, palette treatment, ground, lighting, framing, and output requirements. User customization supplies character traits within that common art direction.

Generation inputs have three explicit layers:

1. **FitFight direction:** the versioned shared rules and a visual style reference.
2. **Character identity:** stock/custom species, the user's original description, structured personality/outfit/accessories, caption where relevant, and approved character reference images.
3. **Scene:** solo companion or group activity, intended participant count, composition, aspect ratio, and scene-specific actions.

Treat user text as customization data, not permission to replace the FitFight rules. Do not send unrelated identity information, HealthKit records, steps, or authentication data to the image provider for this first version. Artwork expresses the cast and activity, not live ranking.

Before choosing a provider/model, run a small, explicitly authorized image-quality trial using current provider documentation and pricing. Evaluate character consistency, multiple reference handling, accessory preservation, duplicate species, framing, actual transparency, and Night/Day appearance. Do not promise exact identity from text prompts alone or assume the prototype tool is the production API.

The custom flow is: choose animal → describe its personality/style → generate draft → inspect → use this companion or revise within the agreed generation allowance. Persist the approved reference image and prompt inputs. Keep the current companion while a new draft is pending or fails.

The TypeScript backend owns provider calls, credentials, persistence, and usage limits. Generation runs as background work with a persisted status, so leaving the screen does not lose a result. The iOS app requests a generation and displays its progress/result. Select the smallest worker mechanism that fits the measured provider behavior and the existing backend; do not introduce a generic workflow platform for this feature.

**Complete when:** custom details survive saving and subsequent group-image tests, a failed generation leaves the current companion usable, and generation count/cost can be inspected before opening the feature to more users.

## Stage 5 — One group illustration per fight

**Product decision pending:** the current app starts fights immediately, including with the owner alone, and accepts later joiners. “Generate at fight start” often produces a solo image before the group exists. This timing question does not block Stages 1–2.

Proposed rule, awaiting Marc's answer: the organizer requests the one group image when the lineup is ready. Snapshot currently accepted participants and their approved companion versions at that moment. Exclude pending invitees and people waiting for the next round. The existing scoring start time and join rules do not change.

Once generated, keep the image for that round. Late joiners still appear in the real roster/standings; the existing image is the cast at generation time. Do not silently regenerate it on a join, refresh, score change, or companion edit. A new recurring round has a new fight ID and can receive its own image under the same chosen rule. If Marc chooses automatic timing instead, record the exact trigger and roster snapshot before implementation.

The server authorizes the action, snapshots the input versions, and records a deduplicated job. Repeated taps or concurrent requests must reuse the same job/output. Enforce one published artwork per fight ID; do not equate that with a guarantee of only one provider charge when an attempt fails. Record attempts and use the provider's idempotency/reconciliation facilities where available before resubmitting ambiguous requests.

The scene appears on fight detail as one image, with the actual score and standings rendered as native text outside it. Artwork generation must not block creating, joining, scoring, or viewing a fight. While artwork is absent, pending, or failed, the screen remains usable with the existing native layout and an honest image status.

Reuse the existing private media/storage approach, with a dedicated companion/fight-art contract. The current media purpose set accepts only `profile` and `fight_post`; do not silently treat generated artwork as an ordinary post or add enum values that break installed clients. Store asset identifiers rather than expiring signed URLs. Artwork visibility must follow the fight's access rules. Account deletion must remove owned companion descriptions/references and invalidate shared generated artwork that includes the deleted companion; use the normal no-art state without automatically spending money regenerating it.

**Complete when:** an authorized group gets one shared illustration with the intended cast, all authorized members receive the same saved output, duplicate requests do not create competing images, and late joins/new rounds follow the agreed rule.

## Verification and review gates

For the native milestone:

- Run the Simulator build, `scripts/check_native_api_boundary.py`, `scripts/check_localizations.py`, and byte-for-byte token comparison. Run the existing native API contract checks if model contracts change.
- Compare native captures with the approved reference at 393 × 852 points; also inspect the actual chosen simulator size, longer French text, larger text settings, and Reduce Motion.
- Exercise live, tied, losing, invited, solo, group, deferred, pending-final-sync, finished, empty, loading, error, and cached/offline display states. Retain the current business rules rather than reproducing only the HTML's happy path.
- Verify preview launch isolation, stock selection, scene fitting, tab navigation, back navigation, form/keyboard behavior, Feed sheets, Health settings, and Versions. Verify real staging writes separately from the local visual-preview mode when a staging session is available.
- Simulator validation establishes native rendering and interaction. Actual step collection, Watch/background delivery, and final real-device sync remain device checks; do not claim them passed from fixture data.

For identity and generation:

- Test ownership, authorized image access, companion version immutability, account deletion, old-client API compatibility, duplicate jobs, failed/ambiguous generation, late joins, and recurring rounds.
- Run `npm run typecheck` and relevant tests from `web/`; run the full suite for shared backend changes. Database checks use the repository's disposable cloud test setup, never a hosted reset.
- Inspect generated outputs for cast count, preserved character details, unwanted text, clipping, and real alpha channels. Test two, three, four, and a larger group, including two users selecting the same species. Decide the supported composition limit from those results without restricting ordinary fight membership.

## Later decisions and deferred work

Before generation implementation, settle the group-image trigger, provider/model, supported customization fields, generation allowance, and acceptable group-composition size. These choices do not delay the fixed-artwork Simulator review.

Paid customization, subscriptions, generated video, real-time effort-dependent artwork, additional activity types, and automatic image regeneration remain future product work. This plan records the direction without building those features.

PRs still require Marc's explicit request and target `develop`. Merges and releases require his instruction. A local Simulator review is independent of the `develop` → `preview` → `main` release train.
