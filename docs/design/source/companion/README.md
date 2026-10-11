# Selected Companion layout

The selected [Companion HTML](../kit/companion-app-proposal.html) supplies the visual direction. The [native design kit](../kit/FitFight%20Design%20System.dc.html) and [tokens](../tokens.json) remain the foundation. The running native/backend behavior wins over simplified prototype interactions.

`originals/` preserves the five images embedded in the selected HTML, byte-for-byte, plus Marc’s hiking-goat effort strip (`originals/goat-hiking-effort.png`). `manifest.json` records stable animal IDs, image dimensions, crop bounds, real transparency, and intended surfaces. No temporary image-generation paths are required.

The solo atlas has an alpha channel. Race and tennis are **opaque** images with separate Night/Day backgrounds; they are never described as transparent cutouts. Both compositions use aspect fit and retain the complete cast and ground. Race is shown only for the four-person Simulator demo cast. Tennis is available as an artwork study below the picker, never as a fabricated Feed post.

Native full-body assets are padded 352 × 400 PNGs. Avatars use 150 × 150 face crops. The extraction keeps the connected character and ground, plus four pixels of antialiasing, removing detached atlas noise and neighboring characters. Originals remain untouched. To reproduce the assets from the repo root, with Pillow installed:

```sh
python3 docs/design/source/companion/prepare-assets.py
python3 docs/design/source/companion/import-effort-forms.py
```

Native artwork is bundled in named `Companion-*.imageset` assets. The app contains no HTML, base64 images, or web view. A chosen stock animal is stored on the account and shown as that person’s avatar to everyone in fights, standings, Feed, and comments. Custom generation and saved group artwork belong to later plan stages.

See [the Simulator handoff](../../companion-simulator-handoff.md) and [captures](screenshots/README.md).

## Planned generation APIs — P0, requested 13 Sep 2026

These are future backend features, not implemented endpoints. The native screens and stock artwork are already in `FitFight/`; they do not require another HTML-to-SwiftUI port. Stock selection is saved on the account so other people and devices see the same companion. Custom is one description stored on the account. Image generation is still later.

A selected companion becomes the person's app avatar on You, fights, standings, Feed and comments. Profile-photo controls must not compete with that choice. The account keeps its real user ID, username and display name; changing an animal never changes membership or scores.

### 1. Custom animal identity and avatar

The native picker is a **grid of stock animals** plus **Custom**. Custom is one text area for species, breed or race, accessories, colors, and anything else that should appear. That text is stored on the profile (`companion_id = custom`, `companion_prompt`) for a later generation job. The picker does not show poses, sport, mood, or other generation internals.

An authenticated TypeScript endpoint is still later: it will take the saved prompt through the chosen image workflow/provider, save the resulting avatar and full-body asset, and return their references. Until then, a custom choice uses initials or a photo as the avatar. Generation failure must preserve the existing selection; only a successful, confirmed result becomes the person's avatar.

Before implementation: select the workflow/provider and server credentials, approve the character recipe and output sizes, and decide generation allowances. The app needs loading, failure and confirmation states. Secrets stay on the server; generated files use the existing owned-media/storage boundary. Account selection and its read contract must ship before generated avatars are shown to other people.

### 2. Five activity forms of the same companion

The native picker no longer shows effort poses. Each of the 12 regular stock animals has five transparent effort forms (`Companion-<id>-effort-1…5`), generated with the Blend Five Fitness Levels workflow and listed in `effort-forms.json`. Today’s step count picks the live pose on You and fights: under 3k resting, 3-6k soft, 6-10k average, 10-15k fit, 15k+ strong. A later generation operation should take the saved identity and reference artwork and create five consistent sport scenes. Activity changes must select an already saved form; they do not generate another image every time the screen opens.

Store each form against the same companion revision. Activity changes select an already saved form; they do not generate another image every time the screen opens. Preserve the animal, breed, face, clothes and accessories across the set. Partial generation must not replace a complete usable set. These forms are presentation only and do not change Steps scoring.

### 3. Group challenge artwork

A third operation uses the participants' saved companion avatars, characteristics and reference images to create one coherent challenge scene. Read the cast from authorized fight membership. Store the scene with the fight/round, participant IDs and companion revisions used to generate it, then reuse it on subsequent reads.

Before implementation: decide when to generate the scene, what membership or customization changes require a new one, and the allowance per fight/round. Every participant must remain recognizable. Keep ordinary standings available while artwork is pending or unavailable. This case is explicitly planned only.

All three cases need authenticated ownership checks, validated requests and provider responses, persistent generation status, and protection against duplicate paid submissions. Server business logic belongs under `web/`; database access belongs in `web/lib/supabase/queries/`. No app-facing Postgres RPCs and no provider keys in iOS.

## Specials, 11 Oct 2026

Thirty Specials in five series of six replace the first forty, which were never
sold: Night Hunters, Royals, Gym Bros, Cozy Club, and Odd Squad.
`limited-editions.json` records each stable ID, series, and English/French name
and caption; the earlier roster remains in git history. Like the regular animals,
every Special has a portrait, a 300 by 300 head avatar, and five effort poses.
`scripts/import-specials.py` turns the generated art (`portrait.png`,
`effort-1.png` to `effort-5.png` per ID) into those imagesets on the 352 by 400
transparent canvas, filling any missing art with a reported placeholder.

The first roster's IDs stay valid on profiles and their edition rows are kept,
marked `retired_at`, so they are never offered again.

All and Specials show these images while sales are on. A tap previews the name
and caption above Buy or Save; it does not change the account. The caption
appears on You and the shared profile after saving. Each Special is sold once per
environment and owned permanently; changing companions or deleting the account
does not release it. Stock animals and custom descriptions remain
shared/unlimited. The server confirms ownership before the app shows a Special
as the selected companion.
