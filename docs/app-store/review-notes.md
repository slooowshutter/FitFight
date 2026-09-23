# App Review Notes

Technical draft updated 23 Sep 2026. Test these instructions on the selected production candidate before pasting. This uses the normal two-person product flow, with no reviewer-only mode, bot, hidden username, or shared Apple credentials.

## Paste into App Review Notes

> FitFight is free Steps competition with friends. No ads, tracking, purchases, entry fees, money wagers, payouts, prizes, or medical diagnosis. Push permission is optional.
>
> SIGN-IN AND TEST SETUP
>
> Sign in with Apple is the only login. Use two reviewer devices and Apple accounts, choosing a different FitFight username on each. FitFight never receives Apple passwords or verification codes.
>
> Onboarding offers read-only Apple Health and optional notifications. Fights work without accessible Steps, but scores may be zero. Reconnect or sync under You → Apple Health Steps.
>
> TWO-PERSON REVIEW PATH
>
> 1. On device A, open You and note its FitFight username.
> 2. On B, open New → Create and keep Steps. Choose Custom, set Start a few minutes ahead and End one hour later. Add A's exact username and an action such as “Loser chooses the next walk.” Finish with Slide to schedule. Preset durations use Slide to start.
> 3. On device A, open Fights and pull down to refresh. Open the invitation and join the Fight. A Fight code or shared invite link also lets the second account join.
> 4. On both devices, sync under You → Apple Health Steps, then open the Fight. Its Stats tab shows the participants, Fight-window totals, daily chart totals, and rank. A custom scheduled Fight starts at the time chosen in step 2.
> 5. After the selected end time, reopen both devices and sync Apple Health again. The Fight may show that final Steps are syncing before its result is frozen. Activity after the exact end time does not count toward that result.
> 6. Open the Fight's Feed tab, post a note or photo/video, and react or reply from the other account. Its menu offers reporting and hiding an author. The app Feed lists posts across your Fights. Feedback has Bugs, Top, and Report, with optional attachments.
>
> Optional notifications include Fight reminders, posts, comments, replies, reactions, and daily status. Manage them under You → Settings → Notifications. The app remains usable when notification permission is declined.
>
> APPLE HEALTH AND SHARING
>
> FitFight requests read access to Step Count and other movement data, including energy, distance, exercise, stand, flights, and workouts. Steps alone score current Fights. The app sends Apple's merged total and chart checkpoints for each exact Fight window, merged daily totals across accessible history, supported individual quantity and category samples with limited source metadata, workout summaries (type, time, active minutes, distance, energy, and effort when available), and explicit sample and workout deletion IDs. Local anchors, GPS routes, and heart rate stay on the phone.
>
> Fight participants see each other's username, profile photo, Fight and daily Steps totals, rank, duration, agreed action, and posts shared with their Fight. Other activity totals and workout summaries remain private to the account. Public Fight listings show join details to signed-in users; posts stay within the selected Fight memberships.
>
> When configured, OpenRouter generates daily-status wording from standing category, participant count, days remaining, sync freshness, and language. It receives no username, account ID, Fight title, exact Steps total, or raw Health samples. The Privacy Policy describes crash reporting and feedback processors as well.
>
> ACCOUNT DELETION
>
> You → Settings → Delete account removes the FitFight profile and username, uploaded Health data and media, posts, feedback, invitations, memberships, scores, and Fights created by that account; removes participation from other Fights; clears local Health sync state; and revokes an available Sign in with Apple credential. The user is then signed out. Copies previously sent to support or crash-processing tools are not automatically deleted by this action; the Privacy Policy explains this limitation and the contact path.
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
