# App Review Notes

Updated 18 Oct 2026 for 1.2.0, submitted unchanged as 1.2.1 on 19 Oct: Connectors, Friends, Fight Marc and the required fight title, built on the approved 1.1.3 (226) notes. Only Steps leave the phone, AI daily status is off in production, and the text fits Apple's 4,000-character limit. `scripts/app-store-release-audit.rb draft` saves this block in App Store Connect. Test these instructions on the selected production candidate before pasting. This uses the normal two-person product flow, with no reviewer-only mode, bot, hidden username, or shared Apple credentials.

## Paste into App Review Notes

> FitFight is free Steps competition with friends. No ads, tracking, entry fees, money wagers, payouts, prizes, or medical diagnosis. Optional in-app purchases unlock companion animals. Push permission is optional.
>
> SIGN-IN AND TEST SETUP
>
> Sign in with Apple is the only login. Use two reviewer devices and Apple accounts, choosing a different FitFight username on each. FitFight never receives Apple passwords or verification codes.
>
> Onboarding offers read-only Apple Health and optional notifications. Fights work without accessible Steps, but scores may be zero. Sync under Profile → Settings → Connectors → Apple Health. An optional Fight Marc screen offers a 30-day Steps fight against the founder's account; Not now skips it.
>
> TWO-PERSON REVIEW PATH
>
> 1. On device A, open Profile and note its FitFight username.
> 2. On B, open New → Create and keep Steps. Type a Title (required). Choose Custom, set Start a few minutes ahead and End one hour later. Add A's exact username and an action such as “Loser chooses the next walk.” Finish with Slide to schedule. Preset durations use Slide to start.
> 3. On device A, open Fights and pull down to refresh. Open the invitation and join the Fight. A Fight code or shared invite link also lets the second account join.
> 4. On both devices, sync under Profile → Settings → Connectors → Apple Health, then open the Fight. Once it starts, its Stats tab shows participants, totals, the daily chart and rank.
> 5. After the end time, sync both devices again. The result freezes once final Steps arrive; activity after the end time does not count.
> 6. Open the Fight's Feed tab, post a note or photo/video, and react or reply from the other account. Its menu offers reporting and hiding an author. The app Feed lists posts across your Fights. Feedback has Bugs, Top, and Report, with optional attachments.
> 7. Friends, at the top of Fights, lets the accounts add each other; each friendship gets a monthly Steps fight. Tap a name for that person's Player card.
>
> IN-APP PURCHASES
>
> The custom character is a consumable and works with a Sandbox account on the production server. Specials are free: open Profile, tap your animal, open the Specials tab, pick any Special and tap Save companion.
>
> - Custom character (com.fitfight.mvp.custom_character): open Profile, tap your animal, open the Yours tab and tap Create your own. Describe an animal. One purchase draws three portraits; pick one, then five fitness poses are generated.
>
> FitFight's server records each purchase, so Restore purchases re-syncs it.
>
> Optional notifications include Fight reminders, posts, comments, replies, and reactions. Manage them under Profile → Settings → Notifications.
>
> APPLE HEALTH AND SHARING
>
> FitFight requests read access to Step Count and other movement data. Steps alone score Fights, and only Steps leave the phone: Apple's merged Steps total and chart checkpoints for each exact Fight window, and daily Steps totals. Other activity, GPS routes, and heart rate stay on the phone. Under Connectors, an optional WHOOP link (needs a WHOOP membership) lets the server read that WHOOP account's sleep, recovery, strain and workouts; it never affects scores.
>
> Fight participants see each other's username, companion, Fight and daily Steps totals, rank, duration, agreed action, and posts shared with their Fight. Posts reach only the Fights and friends the author chooses.
>
> ACCOUNT DELETION
>
> Profile → Settings → Delete account removes the profile, username, uploaded Health data, media, posts, feedback, invitations, memberships, scores and Fights the account created, leaves other Fights, clears local sync state, revokes Sign in with Apple and signs out. Copies already sent to support or crash tools are not deleted automatically; the Privacy Policy explains this.
>
> Privacy Policy: https://fitfight.app/privacy
>
> Support: https://fitfight.app/support
>
> Review contact email: marc@marclamy.com

## Before submission

- Verify the entire path on the exact production candidate. These code-based notes do not prove the production deployment works.
- Apple may request a non-expiring demo account or another immediate-access method. Do not submit credentials for a personal Apple Account.
- Resolve the AI-sharing disclosure/consent and downstream processor-retention questions in [privacy-compliance.md](privacy-compliance.md). Do not claim those gaps are solved by this draft.
