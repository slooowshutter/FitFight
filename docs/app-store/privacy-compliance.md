# App Store privacy and compliance answers

Technical draft updated 15 Sep 2026 for Marc to review before submission. Steps is the only scoring metric, but the current app also collects private activity/workout summaries, posts, media, and notification data. Reconcile these facts against the exact production archive, processor settings, and published policy. This file does not confirm legal compliance or final App Store answers.

## App Privacy

Select **No** for tracking. No data type is used for third-party advertising, developer advertising, data brokerage, or tracking across other companies' apps or websites.

Declare these collected data types:

| App Privacy type      | What FitFight collects                                                                                             | Linked to the user | Purpose           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------ | -----------------: | ----------------- |
| Health                | Apple Health Steps totals, relevant daily chart totals, private activity totals and workout summaries              |                Yes | App Functionality |
| Name                  | Name supplied by Sign in with Apple, when available                                                                |                Yes | App Functionality |
| Email Address         | Apple email or private-relay email                                                                                 |                Yes | App Functionality |
| User ID               | Apple subject, Supabase account ID, FitFight username, referral relationships, and crash-report account identifier |                Yes | App Functionality |
| Device ID             | Encrypted APNs device token and its fingerprint for notification delivery                                          |                Yes | App Functionality |
| Photos or Videos      | Profile photo, Fight post photos/videos, and feedback attachments                                                  |                Yes | App Functionality |
| Gameplay Content      | Fights, invitations, membership state, standings, scores, and results                                              |                Yes | App Functionality |
| Other User Content    | Fight titles/actions, posts, comments, reactions, companion descriptions, and uploaded feedback files              |                Yes | App Functionality |
| Customer Support      | Support emails, in-app bug/feature reports, comments, and report device metadata                                   |                Yes | App Functionality |
| Other Data Types      | Time zone and limited request metadata such as IP address                                                          |                Yes | App Functionality |
| Other Diagnostic Data | Limited server errors, Health sync timing/failure reports, app version and request sizes                           |                Yes | App Functionality |
| Crash Data            | Stack traces and related crash diagnostics sent to PostHog                                                         |                Yes | App Functionality |

The app does not read the address book, GPS routes, or heart rate, and has no purchases, advertising identifiers, or product-interaction capture in its crash integration. Review uploaded files/video audio, stored referral relationships, and diagnostic timing against Apple's exact categories rather than copying older “no photos/videos” answers.

The app privacy manifest now includes Photos or Videos and Device ID alongside the existing categories, no tracking, and the `CA92.1` UserDefaults reason. Apple spells the photo/video value `NSPrivacyCollectedDataTypePhotosorVideos`. Verify the final archive report, SDK manifests, App Store answers, and both published privacy translations agree. Sources: [Apple privacy-manifest data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype) and [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Processor and consent gaps to resolve before submission

- Supabase stores account/application data and uploaded files; Vercel runs the backend. Confirm their live retention settings.
- PostHog receives crash reports linked to the FitFight account UUID when configured. Session replay, screen views and interaction capture are disabled. Deleting the app account does not delete existing PostHog records.
- Configured Notion integration copies feedback text, author handle and attachment links to the backlog. An administrator can send reports, comments, device metadata and attachment links to Cursor. These copies have no automatic account-deletion integration.
- Configured OpenRouter daily-status generation sends standing category, participant count, days remaining, sync-needed status and language to a model provider. It excludes account identifiers, names, Fight titles, exact Steps and raw Health samples. Generation now respects the daily-status preference and requires an authorized active device; the preference defaults on. There is no separate AI-sharing consent flow. Marc must review disclosure, consent, and processor settings before submitting.
- Establish how processor-held copies and routine backups are retained and removed. The draft public policy describes the actual deletion limitation; it is not proof that retention obligations are met.

## Age rating

Use these questionnaire answers:

| Question                                                                               | Answer                                                                      |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| User-Generated Content                                                                 | Yes: usernames, Fight titles/actions, posts, media, comments, and feedback  |
| Contests                                                                               | Recurring fitness rankings and winners; confirm the questionnaire frequency |
| Gambling                                                                               | No                                                                          |
| Simulated Gambling                                                                     | No                                                                          |
| Messaging and Chat                                                                     | Yes: Fight posts and threaded replies                                       |
| Unrestricted Web Access                                                                | No                                                                          |
| Medical or Treatment Information                                                       | No                                                                          |
| Advertising                                                                            | No                                                                          |
| Violence, sexual content, profanity, drugs, alcohol, tobacco, horror, or mature themes | None                                                                        |
| Made for Kids                                                                          | No                                                                          |

Apple calculates the final rating from the completed questionnaire. Marc must confirm the content and frequency answers for this social build; do not reuse the older expected 13+ rating as a guarantee.

## Other compliance fields

| Field                                                      | Answer                                                                                                                                |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Regulated medical device                                   | No: FitFight does not diagnose, prevent, monitor, or treat disease                                                                    |
| HealthKit                                                  | Read-only Steps plus private movement totals/workout summaries; no Health writes                                                      |
| In-app purchases                                           | None                                                                                                                                  |
| Gambling, entry fees, money settlement, payouts, or prizes | None                                                                                                                                  |
| Advertising / IDFA                                         | None; the app does not request tracking permission                                                                                    |
| Non-exempt encryption                                      | No; `ITSAppUsesNonExemptEncryption` is `NO` and the app uses ordinary platform HTTPS/TLS. Recheck the final archive.                  |
| Third-party content rights                                 | No streamed third-party content. Nunito is bundled under the SIL Open Font License; SF Symbols are used under Apple's platform terms. |
| Sign-in                                                    | Sign in with Apple only                                                                                                               |
| Account deletion                                           | Available in the app under You → Settings → Delete account                                                                            |
| Privacy URL                                                | `https://fitfight.app/privacy`                                                                                                        |
| Support URL                                                | `https://fitfight.app/support`                                                                                                        |

Marc must personally confirm the legal/account answers that code cannot determine:

- Individual versus Organization seller enrollment and the correct legal entity.
- DSA trader or non-trader status and any required verified public contact details.
- First-launch countries and regions. A United States-only first release is the smallest compliance surface, but this is a business decision.
- The international App Review contact phone number.
- Whether export documentation is needed for every selected territory, including France.

Do not submit until the production Privacy and Support URLs return `200`, the production backend is live, and every statement above matches the selected binary.
