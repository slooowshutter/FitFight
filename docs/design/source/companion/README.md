# Selected Companion layout

The selected [Companion HTML](../kit/companion-app-proposal.html) supplies the visual direction. The [native design kit](../kit/FitFight%20Design%20System.dc.html) and [tokens](../tokens.json) remain the foundation. The running native/backend behavior wins over simplified prototype interactions.

`originals/` preserves the five images embedded in the selected HTML, byte-for-byte. `manifest.json` records stable animal IDs, image dimensions, crop bounds, real transparency, and intended surfaces. No temporary image-generation paths are required.

The solo atlas has an alpha channel. Race and tennis are **opaque** images with separate Night/Day backgrounds; they are never described as transparent cutouts. Both compositions use aspect fit and retain the complete cast and ground. Race is shown only for the four-person Simulator demo cast. Tennis is available as an artwork study below the picker, never as a fabricated Feed post.

Native full-body assets are padded 352 × 400 PNGs. Avatars use 150 × 150 face crops. The extraction keeps the connected character and ground, plus four pixels of antialiasing, removing detached atlas noise and neighboring characters. Originals remain untouched. To reproduce the assets from the repo root, with Pillow installed:

```sh
python3 docs/design/source/companion/prepare-assets.py
```

Native artwork is bundled in named `Companion-*.imageset` assets. The app contains no HTML, base64 images, or web view. A chosen stock animal is stored on the account and shown as that person’s avatar to everyone in fights, standings, Feed, and comments. Custom generation and saved group artwork belong to later plan stages.

See [the Simulator handoff](../../companion-simulator-handoff.md) and [captures](screenshots/README.md).

## Planned generation APIs — P0, requested 13 Sep 2026

These are future backend features, not implemented endpoints. The native screens and stock artwork are already in `FitFight/`; they do not require another HTML-to-SwiftUI port. Stock selection is saved on the account so other people and devices see the same companion. Custom generation is still later.

A selected companion becomes the person's app avatar on You, fights, standings, Feed and comments. Profile-photo controls must not compete with that choice. The account keeps its real user ID, username and display name; changing an animal never changes membership or scores.

### 1. Custom animal identity and avatar

Add **Custom** to companion selection. The person supplies an animal, optional breed, and appearance instructions such as sunglasses, a hat, clothing and colours. Keep both the original prompt and structured characteristics, with an owner ID, companion ID and revision. Store the selected stock ID or custom companion ID on the account.

An authenticated TypeScript endpoint creates the companion through the chosen image workflow/provider, saves the resulting avatar and full-body asset, and returns their references. The profile read API returns the chosen companion and its assets so every native surface uses the same identity. Save the prompt/workflow version and reference artwork required to reproduce the character. Generation failure must preserve the existing selection; only a successful, confirmed result becomes the person's avatar.

Before implementation: select the workflow/provider and server credentials, approve the character recipe and output sizes, and decide generation allowances. The app needs loading, failure and confirmation states. Secrets stay on the server; generated files use the existing owned-media/storage boundary. Account selection and its read contract must ship before generated avatars are shown to other people.

### 2. Five activity forms of the same companion

A separate generation operation takes the saved identity, customization and reference artwork and creates **five consistent forms**. Form 1 sits on a couch with a blanket and a cup of tea; form 5 is tall and very muscular. Forms 2–4 and the activity thresholds/window still need a product decision.

Store each form against the same companion revision. Activity changes select an already saved form; they do not generate another image every time the screen opens. Preserve the animal, breed, face, clothes and accessories across the set. Partial generation must not replace a complete usable set. These forms are presentation only and do not change Steps scoring.

### 3. Group challenge artwork

A third operation uses the participants' saved companion avatars, characteristics and reference images to create one coherent challenge scene. Read the cast from authorized fight membership. Store the scene with the fight/round, participant IDs and companion revisions used to generate it, then reuse it on subsequent reads.

Before implementation: decide when to generate the scene, what membership or customization changes require a new one, and the allowance per fight/round. Every participant must remain recognizable. Keep ordinary standings available while artwork is pending or unavailable. This case is explicitly planned only.

All three cases need authenticated ownership checks, validated requests and provider responses, persistent generation status, and protection against duplicate paid submissions. Server business logic belongs under `web/`; database access belongs in `web/lib/supabase/queries/`. No app-facing Postgres RPCs and no provider keys in iOS.
