# Google sign-in control

The native button uses Google's light treatment: white fill, `#747775` border,
`#1F1F1F` text, Google Sans Medium, and the supplied multicolor gradient G.
Provider colors are named tokens in `tokens.json`, copied to the app bundle.
The centered content, 44pt height, and 6pt corners align with the Apple control.
There is no shadow. Busy state disables the entire control and reduces opacity.

Sources retrieved 19 September 2026:

- [Google branding guidelines](https://developers.google.com/identity/branding-guidelines)
- [Official PNG/SVG assets](https://developers.google.com/static/identity/images/signin-assets.zip)
- [Google Sans font and OFL](https://github.com/google/fonts/tree/main/ofl/googlesans)

`GoogleSignInIcon` contains the unmodified 3x iOS light icon PNG from the asset
bundle. The SwiftUI label shows its center 20pt logo at the original scale,
clipping the surrounding icon-button border. Google Sans is instantiated at
weight 500, optical size 17, grade 0, and subset to Basic Latin/Latin-1 for the
English/French labels. The OFL is included with the font in app resources.
