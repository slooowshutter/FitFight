# App Store screenshots: 1.1.1

[Open the English/French gallery](index.html).

## Prepared assets

- Six English screenshots in `en-US/` and six French screenshots in `fr-FR/`.
- Every image is a 1320 x 2868 JPEG from a running iPhone 17 Pro Max simulator.
- Screens: Fights, a live Fight, creation, an invitation, You, and Feed.
- `AppIcon.png` is byte-identical to the bundled beige FF on green icon.

The final refresh uses native source `8816e90`, merged into develop as `25f8ac8`,
with existing Companion sample accounts and Steps. The You screen shows `1.1.1`,
local build `1`, and the production display configuration. Other screens omit the
version label, matching the current app. These captures do not prove production
sign-in, real HealthKit sync, or live backend compatibility. The gallery retains
its capture build label; the production archive was verified separately.

## Capture and verification

Marc explicitly authorized his Mac and the iOS simulator for these captures.
Release archives and uploads still use GitHub-hosted macOS. Safari is used for
App Store Connect and gallery review.

The Debug simulator build passed with signing disabled. A temporary production
`BuildEnv.swift` was used for the version label and restored after compilation.
No production configuration was committed for the staging build.

| Launch environment | Value |
| --- | --- |
| `SIMCTL_CHILD_FF_COMPANION_PREVIEW` | `1` |
| `SIMCTL_CHILD_FF_SHOOT` | `1` |
| `SIMCTL_CHILD_FF_SHOT` | `fights`, `fight`, `new`, `invitation`, `you`, or `feed` |

Use `-AppleLanguages '(en)' -AppleLocale en_US` for English and
`-AppleLanguages '(fr)' -AppleLocale fr_FR` for French. Wait for the scene to settle,
then capture with `xcrun simctl io <device-id> screenshot --type=jpeg <output.jpg>`.
The simulator status bar is set to 9:41 with full battery and signal.

All twelve images passed dimension, opacity, and text checks. Both You captures
show 1.1.1 and prod; no capture contains preview-only labels or controls.
The English and French layouts were visually checked.

## Release status

All twelve screenshots are uploaded and processed. English/French listing text,
release notes, review instructions, privacy answers, and the updated age rating
are saved. Production **1.1.1 (202)** was submitted at 01:42 Paris time on
16 September 2026 and is **Waiting for Review**, with manual release enabled.
The current public build remains 1.0.0 (113).

See [release preparation and data-transfer plan](release-1.1.0.md) and
[current deployment evidence](../../status.md). Production promotion and the initial
beta account/history/media transfer are complete. Repeat the beta catch-up before
the manual public release.
