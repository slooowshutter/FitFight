# App Store screenshots: 1.2.0

[Open the English/French gallery](index.html).

Six English screenshots in `en-US/` and six French screenshots in `fr-FR/`, 1320 x 2868 JPEGs for the 6.9-inch iPhone set. They replace the 15 Sep 2026 set, which is still live on the App Store.

Marc asked on 16 Oct 2026 for the 1.2.0 screenshots to match the fitfight.app redesign of 15 Oct. They use the website's sample people and fights: Alex (you, Tiger), Leo (Silverback), Nina (Capybara), Sam (Hedgehog) and Theo (Panda), in Walk Wars, Eat it and Step it Up, with 8,432 steps today and the website's three Feed posts.

| File | Screen |
| --- | --- |
| `01-fights.jpg` | Fights: Walk Wars +860, Step it Up +2,840, Eat it -1,260 |
| `02-fight.jpg` | Eat it, a live 1v1 against Theo |
| `03-new.jpg` | New: Create, Join or Post |
| `04-invitation.jpg` | An invitation from Sam |
| `05-you.jpg` | Profile: Alex, the Tiger and statistics |
| `06-feed.jpg` | Feed: posts from Leo, Nina and Sam |

## Capture

The Screenshots workflow (`.github/workflows/ios-screenshots.yml`, step "Capture App Store screenshots") builds the Debug simulator app with the production `BuildEnv.swift`, then launches it on an iPhone 17 Pro Max simulator with `FF_COMPANION_PREVIEW=1`, `FF_SHOOT=1` and `FF_SHOT` set to `fights`, `fight`, `new`, `invitation`, `you` or `feed`, in English and French. The status bar shows 9:41. The images come from the `app-store-screenshots` and `app-store-screenshots-fr` artifacts. No Mac other than GitHub's hosted runner was used. Look at every image before committing it: a run on 16 Oct caught an iOS "Ready for Apple Intelligence" banner on one French capture, and a rerun fixed it.

The Profile screen shows the simulator build's version line, `1.2.0 · build 1 · prod`. The captures use sample data only; they do not prove sign-in, Apple Health sync or the live backend.

## Upload

Not uploaded. 1.1.3 (226) is still in App Review, so App Store Connect cannot hold a 1.2.0 version yet. When it can, `scripts/app-store-release-audit.rb prepare` uploads these twelve images, replacing the 15 Sep set; save the 1.2.0 copy in [metadata](../metadata.md) with them.
