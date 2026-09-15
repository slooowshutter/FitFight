# App Review Notes

Technical draft updated 15 Sep 2026. Test these instructions on the selected production candidate before pasting. This uses the normal two-person product flow, with no reviewer-only mode, bot, hidden username, or shared Apple credentials.

## Paste into App Review Notes

> FitFight is a free social fitness app for Steps competitions between people who know each other. It has no advertising, tracking, in-app purchases, entry fees, money wagers, payouts, prizes, or medical diagnosis. Push permission is optional.
>
> SIGN-IN AND TEST SETUP
>
> Sign in with Apple is the only login method. To compare two participants, use two reviewer devices and two Apple accounts available to App Review. On each device, sign in and choose a different FitFight username. No Apple ID password or verification code is shared with FitFight.
>
> New accounts are offered Apple Health, optional notifications, and an explanation of the Feedback tab. Apple Health access is read-only. If no Steps are accessible, a Fight can still be created and joined, but its score may be zero. You can reconnect or sync under You → Apple Health Steps.
>
> TWO-PERSON REVIEW PATH
>
> 1. On device A, open You and note its FitFight username.
> 2. On device B, open New → Create, keep Steps, and choose a duration. The presets are 3 days, 1 week, 2 weeks, and 1 month. For a short test, choose Custom, set Start a few minutes in the future and End one hour later. Add device A's exact username, enter an action such as “Loser chooses the next walk,” and finish the review screen using Slide to schedule. A preset duration uses Slide to start instead.
> 3. On device A, open Fights and pull down to refresh. Open the invitation and join the Fight. A Fight code or shared invite link also lets the second account join.
> 4. On both devices, sync under You → Apple Health Steps, then open the Fight. Its Stats tab shows the participants, Fight-window totals, daily chart totals, and rank. A custom scheduled Fight starts at the time chosen in step 2.
> 5. After the selected end time, reopen both devices and sync Apple Health again. The Fight may show that final Steps are syncing before its result is frozen. Activity after the exact end time does not count toward that result.
> 6. Open the Fight's Feed tab, post a note or optional photo/video, and use the other account to react or reply. The post menu provides reporting and hiding an author. The app's Feed tab lists posts across your Fights. The separate Feedback tab has Bugs, Top, and Report for app feedback; reports may include attachments.
>
> Optional notifications include Fight reminders, posts, comments, replies, reactions, and daily status. Manage them under You → Settings → Notifications. The app remains usable when notification permission is declined.
>
> APPLE HEALTH AND SHARING
>
> FitFight requests read access to Step Count and other movement data, including energy, distance, exercise, stand, flights, and workouts. Steps alone score the current Fights. The app sends Apple's merged total for each exact Fight window and relevant merged daily Steps totals. It may also store private activity totals and workout summaries, including type, time, active minutes, distance, energy, and effort when available. It does not upload raw Health samples, GPS routes, heart rate, or device/source metadata.
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
