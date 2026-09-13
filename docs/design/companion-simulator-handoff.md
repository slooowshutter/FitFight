# Companion — native Simulator handoff

13 September 2026. The fixed-artwork native implementation is built, installed and checked on **iPhone 17, iOS 26.5**, ready for Marc's visual review. The native review gate precedes account synchronization and generation. This is not a release or a completed end-to-end staging product test.

## Open the review

From the repository root:

```sh
./scripts/run-companion-preview.sh
```

The script builds the actual `FitFight` scheme with signing disabled, uses workspace-local DerivedData and package checkouts, installs the app, and launches the marked preview. It selects the reviewed iPhone 17 / iOS 26.5 runtime. To choose another installed Simulator, pass its UDID:

```sh
./scripts/run-companion-preview.sh ACE4AD1B-1576-4FEF-B1C7-2ED50957D50B
```

The shared **Companion Preview** Xcode scheme also launches Debug with `--companion-preview`. The ordinary FitFight scheme retains its normal launch path.

Open **You → Companion preview** below Look for display states and Night/Day. Marc requested removal of the top preview banner; the fixture controls and write guards remain. Under **You**, tap **Try another companion**, select an animal, scroll to **Use this companion**, and return to Fights. The choice lasts until the preview process restarts. The tabs, fight detail, recurring History, Feed, New, settings, and sheets are the real SwiftUI views.

The three active examples include a winning group and losing duel. The invitation offers this round or the next. Display controls also supply tied, solo, deferred, pending final sync, finished, empty, loading, and cached/offline examples. Preview codes are **K7M2**, **H8P4**, and **B4K9**.

## What changed

- Custom duration sets an exact future start and end date/time, validates their order, and shows both in review. The preset durations still start immediately. Scheduled fights show their start time. Long custom windows retain the existing 41-day chart limit; the fight score still uses the exact full window.
- Choosing a companion updates your avatar on You, fights, standings, Feed and comments. The choice is still local to this session. Apple Health shows a collapsed summary with More settings for access requests and diagnostics. Previously reviewed permissions must be changed in Health → profile → Apps → FitFight ([Apple guidance](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios)).
- The [Companion README](source/companion/README.md#planned-generation-apis--p0-requested-13-sep-2026) describes three future P0 generation operations. None is implemented.

- Fights, New, and You share the personal companion introduction. Fights uses the HealthKit store's daily total; fight detail uses the fight's exact scoring window. Missing daily data is explicitly unavailable or connection-needed.
- Marc's review refinement: the shared introduction uses only the ground painted into the animal asset. The extra green ellipse beneath Fights, New and You was removed.
- Marc’s density refinement: the Fights header combines its title, daily steps and a 156-point companion. Current / Invited / Past filters reuse the app’s compact `FFSegmented` control beside Challenges; only the selected group appears. The old live/waiting counts and YOUR COMPANION label are removed; “A little further. Together.” remains above the daily steps.
- Fight detail places the action beneath its title, trims the group scene’s empty margins into 168 points, and shows standings immediately after the score. Stats keeps one countdown; codes and existing links move to Share alongside Stats, History (when available) and Feed. Invitations keep the title and inviter centered, then align rules and each round choice to the left. The shared screen CTA now uses the ordinary full-width button; only New’s confirmation uses a slider.
- Countdowns use whole months, weeks, days or hours; below two days they add hours, and below two hours they add minutes. Below one hour they show minutes, with a minimum of one minute until the deadline. Finished and pending results retain their actual end date. Existing settlement, invitations, standings, charts, History, Feed, sharing and leaving remain in their original stores and API paths.
- Feed keeps membership-based fight-post reading, reactions, comments and moderation. Its composer is the only posting entry: select one or more fights, then add a note and up to four photos or one video through Media. The channel menu stays open between selections; tagging and the inline fight composer are removed. Post headers put the author first, then a plain channel label followed by the relative time on the left; the ellipsis aligns with the top row. Tab icons use 20-point square frames with equal six-point padding, and the bar has symmetric vertical padding. Fixture posts contain ordinary sample text; the tennis illustration is not a fake post.
- Twelve stock animals have clean body/avatar assets. The original atlas and four opaque Night/Day scene files are preserved with an asset manifest and reproducible extraction script. Both scenes retain the full cast and ground.
- Stock selection is a session-only design control. Live account photos and initials remain independent; other accounts do not acquire invented animal identities. The fixed four-animal scene is limited to the four-person demo, identified in You → Companion preview. Tennis appears below the demo picker as an artwork study.
- The bottom bar has top/bottom spacing around its controls; nested winning standings use outer radius minus the inset. Share now includes the fight link with or without an optional referral code.
- Charts have a numeric scale and per-day readout. Tap histogram/stack/heat days, or touch and drag Line/Pace; Dots and Track are removed. Ring/Oval/Heat avatars use account photos (the selected animal in the demo). Stack clipping follows the actual column height. These are daily buckets; ring/oval totals explicitly describe the days shown.
- English/French strings and the `1.0.0` release note are included. The marketing version and both token files are unchanged.
- Creation review now passes the two arguments expected by its duration/end localization key. Runtime checking exposed the previous three-argument interpolation, which displayed the repeat text where the end date belonged. Recurrence remains explicit in the agreement below it.

## Preview boundary

The entry flag only works when both `DEBUG` and `targetEnvironment(simulator)` are true. The fixture helpers and preview controls are excluded from Release. Root launch, foreground, URL handling, Auth listening, update polling, backend refresh, push callbacks and HealthKit callbacks are guarded. Fixture sessions never construct the lazy Supabase Auth client.

Creating/joining/leaving fights, publishing posts/comments, media/profile writes, sign-out and account deletion stop at their existing submission boundaries with a preview message. Health actions show the same notice. Preview selection and theme use transient in-memory stores. No alternative mock backend was added.

The ordinary signed-in path still uses the existing API and Auth. The existing scheduled-create contract now keeps invited future fights in `scheduled`, so the clock can start them. No schema changed, no generation provider was selected, and no paid generation or hosted database operation ran.

## Verification

| Check | Result |
| --- | --- |
| Actual FitFight scheme, Debug and Release, iOS Simulator | Passed with Xcode at `/Applications/Xcode-beta.app/Contents/Developer`; build logs are workspace-local under `.context/`. |
| Release preview gate | Compiled `CompanionPreview.swift` without `DEBUG` for the Simulator and executed it with both preview flags set; `isEnabled` remained false. |
| Native API contracts | Existing `tests/APIContractTests.swift` passed against `contracts/fixtures`: profile, onboarding, cached profile, extra fields and fight snapshot. |
| Native API boundary | `python3 scripts/check_native_api_boundary.py` passed. |
| Localization | `python3 scripts/check_localizations.py` passed: 695 app strings, 3 Info.plist strings, 109 release notes. |
| Countdown thresholds | `tests/RemainingTimeTests.swift` passed, including two-hour, one-day, two-day, week and month boundaries. |
| Tokens / whitespace | Byte-for-byte token comparison and `git diff --check` passed. |
| Native visual captures | 393 × 852 SwiftUI captures in Night/Day and English/French; selected screens also rendered at Accessibility 3 text size. Hero clipping and a French label overflow were fixed after inspection. |
| Artwork | All 12 bodies/avatars inspected on both surfaces. Atlas has real alpha; group scenes are opaque. No neighboring atlas animals enter the prepared body crops. |
| Density-review interaction | Current / Invited / Past isolate their respective fights; opening an invitation and going Back preserves the filter. Share opens separately, leaving the score followed by standings in Stats. English/French and Night/Day captures verified, including Accessibility 3 titles and actions. |
| Custom schedule / avatar / Health | Debug and Release Simulator builds, native API contracts, backend typecheck and all 166 backend tests passed. Regression coverage checks exact custom timestamps, reversed ranges and scheduled fights with invitees, plus the existing immediate-start request. In Simulator, selecting Raccoon updated the profile avatar; More settings expanded/collapsed Health details; an end before the start disabled Next; review showed both timestamps and Slide to schedule retained the preview write guard. |
| Latest polish | The latest icon-padding and plain-channel-label refinement passed a Debug Simulator build and localization checks. French invitation layout and its tap-to-join guard, plain channel label, standalone share link and multi-channel selection checked in Simulator; the rebase retains develop’s fight-only Feed and refreshes both locales’ captures. Tapping Day 3 in Stack showed 5,280 / 4,752 / 4,149 / 3,870 steps; Line retained that selection. |
| Actual Simulator interaction | Tabs/back, Fox selection and persistence across tabs, Day appearance, group detail, recurring History, New's five steps and keyboard editing, public/code join, invitation choices, Feed composer/destination selection, nested comments, Health settings and Versions checked. |
| Preview submissions | Slide to start's accessibility confirmation, post, comment, next-round invitation, sign-out and account deletion were exercised; the app showed the preview notice and retained the fixture account/data. |
| Alternate states | Tied, solo, deferred, pending, finished, empty, loading and cached/offline checked through fixture controls, now under You → Companion preview. Pending row copy was corrected to use its new state rather than the original fixture's remaining time. |
| Reduce Motion | Enabled in the Simulator's Settings, returned to the app and tapped the companion; no visible response, consistent with its Reduce Motion guard. The Simulator setting was restored afterward. |
| Launch script | Shell syntax checked; its build/install/launch commands were exercised during implementation. |

The selected layout and native captures are indexed in [screenshots](source/companion/screenshots/README.md). The [original HTML](source/kit/companion-app-proposal.html) remains tappable.

### Remaining review and device checks

Marc's visual acceptance is the next checkpoint.

The media picker showed both photo and video choices, but attachment loading and actual uploads were not verified. Horizontal chart dragging was not manually verified because coordinate-driven Simulator actions failed with `noWindowsAvailable`; tap selection was checked. Real staging writes require an authorized signed-in staging session and were not exercised. Real HealthKit collection, Watch/background delivery, and final device sync remain device checks; sample totals establish neither data collection nor synchronization.

## Reproduce native captures

Set the export variable while launching the script, or use this command after the Debug app is installed:

```sh
SIMCTL_CHILD_FF_COMPANION_PREVIEW=1 SIMCTL_CHILD_FF_COMPANION_EXPORT=1 \
  xcrun simctl launch --terminate-running-process \
  ACE4AD1B-1576-4FEF-B1C7-2ED50957D50B com.fitfight.mvp \
  --companion-preview -AppleLanguages '(en)' -AppleLocale en_US
```

Use `'(fr)'` and `fr_FR` for French. The app writes 68 PNGs and `done.txt` to `Documents/companion-shots/` inside its Simulator data container. Find that container with:

```sh
xcrun simctl get_app_container ACE4AD1B-1576-4FEF-B1C7-2ED50957D50B com.fitfight.mvp data
```

All exports render the production SwiftUI views with fixture stores at 393 × 852 points, one pixel per point. Static exports omit system status icons. Large-text exports use Accessibility 3. The loading export uses a static refresh symbol; the composer uses its placeholder and menu label during export because UIKit-backed controls cannot be captured by ImageRenderer. The composer is captured as a sheet, without root tabs or a duplicate version line.

After native review, continue Stage 3 for account-backed stock identity. Stages 4–5 still require the generation trial and the group-image timing/allowance decisions in the plan. This feature PR targets develop; no merge, TestFlight upload, deployment or production change was made.
