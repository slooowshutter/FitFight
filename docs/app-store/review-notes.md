# App Review Notes

This is the honest normal two-person path. There is no reviewer-only mode, bot, hidden username, or password login. FitFight uses Sign in with Apple and requires another signed-in participant for its core Fight flow.

## Paste into App Review Notes

> FitFight is a free social fitness app for private Steps competitions between people who know each other. It has no advertising, tracking, in-app purchases, entry fees, money wagers, payouts, prizes, medical diagnosis, or push-notification requirement.
>
> SIGN-IN AND TEST SETUP
>
> Sign in with Apple is the only login method. The normal Fight flow requires two reviewer devices and two Apple accounts available to App Review. On each device, sign in and choose a different FitFight username when prompted. No Apple ID password or verification code is shared with FitFight.
>
> On each device, open You → Apple Health Steps → Connect and choose the Apple Health read permissions you want to allow. Apple Health access is read-only. If a device has no accessible Steps, the Fight can still be created and accepted, but its displayed score may be zero.
>
> TWO-PERSON REVIEW PATH
>
> 1. On device A, open You and copy its FitFight username.
> 2. On device B, open New, add device A's exact username, choose 1 hour, enter an action such as “Loser chooses the next walk,” and tap Start fight.
> 3. On device A, open Fights and pull down to refresh. The invitation appears at the top. Open it and tap Accept challenge.
> 4. On both devices, open You → Apple Health Steps to sync, then open the Fight and pull down to refresh. Both devices show the same participants, Fight-window totals, daily chart totals, and rank.
> 5. The 1-hour option is included so the ending flow can be tested without waiting several days. After the hour ends, reopen both devices and sync Apple Health again. The Fight may briefly show “Syncing final steps” while it receives the end-of-window totals. Steps after the exact end time do not count toward the final result.
>
> OPTIONAL FEATURES IN 1.1.0
>
> You can schedule or repeat challenges, choose a companion under You, and share posts, photos, and videos in Feed. The post composer shows its destination. Reporting and blocking controls are available for user content. Notifications are optional and can be configured in You → Settings; the app works when permission is declined. Pull to refresh retrieves new invitations and scores.
>
> APPLE HEALTH AND SHARING
>
> FitFight requests read access to Step Count and additional activity types: active/resting energy, distances, exercise, stand, flights, wheelchair pushes, and workouts. It sends merged Fight/daily step totals, private daily activity totals, and workout summaries (identifier, type, time, duration, and available activity measurements). Only Steps score the current challenges. Extra activity summaries remain private and currently prepare future challenge types. It does not upload raw Health samples, GPS routes, heart rate, or device/source metadata. Accepted participants see each other's FitFight username, Fight and daily Steps totals, rank, duration, and agreed action.
>
> ACCOUNT DELETION
>
> You → Settings → Delete account permanently removes the FitFight profile and username, uploaded Health summaries, authored posts and media, invitations, memberships, scores, and Fights created by that account; removes participation from other Fights; clears local Health sync state; and revokes an available Sign in with Apple credential. The user is then signed out.
>
> Privacy Policy: https://fitfight.app/privacy
>
> Support: https://fitfight.app/support
>
> Review contact email: marc@marclamy.com

## Submission warning

This path depends on App Review using two devices/accounts. Apple may still request a non-expiring demo account or a different immediate-access method. Do not claim a solo review path exists, and do not submit credentials for a personal Apple Account.

Before pasting these notes, test every numbered instruction on the exact production candidate and replace any wording that does not match what the reviewer will see.

## Release verification

Prepared for 1.1.0 on 15 September 2026. Production candidate testing is pending. The extra Health collection has no current challenge-scoring purpose and must be explicitly reviewed before submission; do not claim it is Steps-only. Privacy disclosures and the App Store privacy questionnaire must agree with the shipped binary.
