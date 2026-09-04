# Current Apple review blockers after the Steps-only cut

Research refreshed: **30 August 2026**

Repository reviewed: **`7b21323`**
Scope: concise addendum to [the original first-review audit](app-store-first-review-readiness.md), using Apple primary sources only.

## Bottom line

The product concept is reviewable. Apple explicitly describes a group of friends using a social app for a daily step-count challenge as a HealthKit use case. With clear permission and privacy handling, participant-visible aggregate Steps are therefore not categorically prohibited. [Apple HealthKit overview](https://developer.apple.com/documentation/healthkit/)

The remaining likely rejection risks are below. “Required” means Apple states the requirement or App Store Connect will not accept a complete submission. “Recommended” means it is a FitFight first-pass hardening measure, not a universal Apple form requirement.

## Ranked blockers

| Rank | Remaining work | Classification | Where | Current FitFight status |
| ---: | --- | --- | --- | --- |
| 1 | Moderate the typed action and usernames: filtering, reporting, blocking, published contact, and a real timely-response process | **Required while free text remains** | App + backend + operations | **Missing**, except the support contact page exists in code |
| 2 | Give App Review immediate access to pending, accepted/live, and completed fights without requiring another reviewer or waiting 3–30 days | **Required** | App/backend + App Store Connect | **Missing** |
| 3 | Complete account deletion, including Sign in with Apple revocation and erasure/anonymization of retained identifiers and user-authored text | **Required** | App + backend | **Incomplete** |
| 4 | Deploy working public Privacy and Support URLs and make all privacy disclosures/forms match the final production behavior | **Required** | Web + App Store Connect | **Pages exist in code but both production and staging URLs returned 404 during this check** |
| 5 | Produce and test an actual production candidate with a live production backend; remove beta/staging and obsolete wager language from every reviewer-visible surface | **Required** | CI/app/web + App Store Connect | **Only staging TestFlight is proven; the public homepage still says “Private beta” and visible historical release notes still mention betting/money** |
| 6 | Complete the age rating and other App Store Connect declarations accurately | **Required to submit** | App Store Connect | **Not verifiable from the repository** |
| 7 | Confirm the seller is the appropriate legal entity for an app requiring sensitive Health information | **Required/conditional** | Apple Developer account | **Unknown** |

## 1. Free-text action and usernames are UGC

The optional loser action and fight title are arbitrary text sent to other users. Usernames are user-authored and visible too. Apple Guideline 1.2 requires UGC/social services to provide:

- filtering before objectionable material is posted;
- a way to report offensive content and an operationally timely response;
- the ability to block abusive users; and
- published contact information. [Apple App Review Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/)

FitFight currently has the contact surface in [support/page.tsx](../../web/app/support/page.tsx), but no filtering, Report, or Block flow. Decline alone is not the same as blocking. This is the most obvious remaining code-level rejection risk.

Minimum launch implementation:

1. Enforce action and username rules on the server, not only in Swift.
2. Add **Report action/user** from an invitation or fight.
3. Add **Block user** and enforce the block when creating invitations and loading interactions.
4. Give support a documented moderation queue and response/removal process.

Invitation rate limits, audit logs, and concise acceptable-use rules are **recommended** operational safeguards. They are not substitutes for Apple’s four required controls. Unsafe, coercive, illegal, sexual, self-harm, or humiliating actions should be prohibited; Apple separately warns against challenges that risk physical harm. [Apple Guideline 1.4.4](https://developer.apple.com/app-store/review/guidelines/)

## 2. The reviewer must be able to see the core product immediately

Apple requires full review access, a live backend, and either an active demo account or a fully featured demo mode. Guideline 2.1 says a demo mode used instead of an account because of legal/security constraints needs prior Apple approval. [Apple Before You Submit and Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/)

App Store Connect separately requires non-expiring demo sign-in details when login is required, plus notes and contact details. [Apple platform version and App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

Sign in with Apple plus a two-person, multi-day flow does not currently provide a practical review path. Choose and prove one path before submission:

- a prior-approved, clearly labeled demo mode containing pending, live, and completed fights; or
- a durable review account plus a controlled reviewer opponent/bot that can create and advance the relevant states.

The reviewer must not need to share an Apple Account password, recruit a second person, or wait three days. Review Notes should give exact navigation, explain Apple Health read-only access, state what participants see, and describe deletion.

## 3. Delete Account is visible, but deletion is not complete

Apple requires in-app initiation of deletion of the complete account and associated personal data, not mere deactivation. Apple also says shared user-generated content is expected to be deleted unless retention is legally required and explained. [Apple account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/)

The current deletion query removes Health rows and login access, but it leaves a stable profile row/handle when fight history exists and does not remove the fight owner’s typed action. See [delete-account-supabase-query.ts](../../web/lib/supabase/queries/delete-account-supabase-query.ts). Preserving a genuinely non-identifying score result may be defensible; retaining the user’s stable handle or authored action is not the same as anonymization.

FitFight also does not revoke Sign in with Apple. Apple’s current technote says the `/auth/revoke` endpoint is the programmatic way to invalidate the authorization and describes a manual-revocation fallback only when no usable token/code exists. [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple) and [token revocation endpoint](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)

Required finish:

- revoke the Sign in with Apple authorization server-side, or implement Apple’s documented manual fallback;
- randomize/remove the handle and other re-linking identifiers;
- remove or replace user-authored action text in shared history;
- clear local Health/upload state and credentials; and
- test deletion, relaunch, and clean re-registration with the same Apple identity.

## 4. Privacy and Support must be live, not merely implemented

Apple requires a Privacy Policy URL for iOS, an easily accessible in-app privacy-policy link, and a policy that identifies collection, uses, third parties, retention/deletion, and consent withdrawal. [Guideline 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/) and [Apple App Store Connect privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)

Apple also requires a Support URL that leads to actual contact information. [Apple platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

Observed during this refresh:

- `https://fitfight.app/privacy` → **404**
- `https://fitfight.app/support` → **404**
- `https://staging.fitfight.app/privacy` → **404**
- `https://staging.fitfight.app/support` → **404**

The new pages and in-app links are good implementation work, but deployment is a stop-ship requirement. Replace vague retention language such as “as reasonably needed” with honest periods or criteria before publishing.

The App Store privacy label is a separate required submission item and must cover FitFight and integrated third parties. Apple defines HealthKit data as **Health**, handles/account IDs as **User ID**, multiplayer matching/game logic as **Gameplay Content**, and arbitrary typed actions as **Other User Content**. Support and retained diagnostics must also be declared when Apple’s collection definition applies. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)

The app now has `PrivacyInfo.xcprivacy` and the `CA92.1` UserDefaults reason, which addresses the known required-reason API. Still reconcile the exact production archive’s combined privacy report and App Store Connect answers. Since May 2024, submissions using required-reason APIs without valid declared reasons are not accepted. [Apple required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

There is also a current disclosure mismatch: [FightDetailView.swift](../../FitFight/FightDetailView.swift) shows every accepted participant's per-day Steps in “Every day so far,” while the Health purpose string, New Fight disclosure, and privacy page say participants see only the Fight total and rank. The lowest-risk launch fix is to remove peer daily totals and keep only total/rank. If daily sharing remains, disclose it explicitly before both creation and acceptance and update the purpose string, privacy policy, and App Store privacy answers to match.

## 5. Submit a complete production product, not the staging/beta presentation

Apple requires a final, on-device-tested binary, live backend, functional URLs, accurate metadata, and no placeholder/beta content. [Guidelines 2.1, 2.2, and 2.3](https://developer.apple.com/app-store/review/guidelines/)

The simplified app is much closer, but before review:

- create/prove the cloud production archive path and production configuration;
- run sign-in, invite, accept, decline, scoring, ending, Health deny/revoke, and deletion with two real accounts on the exact candidate;
- remove “Private beta” from the public website;
- ensure the App Store name is not “FitFight MVP”; and
- keep reviewer-visible Versions notes from implying that wagering, pots, payouts, or hidden experimental features remain in the product.

This is completeness work, not a request to add more features. Native Apple Health integration, persistent private challenges, invitations, and standings provide credible utility under Guideline 4.2; **minimum functionality is unlikely to be the rejection reason once the complete production flow works**. [Apple Guideline 4.2](https://developer.apple.com/app-store/review/guidelines/)

## 6. Required App Store Connect answers

These are outside the app but can block submission or create a review mismatch:

- **Age rating:** declare **User-Generated Content** and **Frequent Contests**. Apple defines contests to include rankings, personal goals, and sport/fitness contests; frequent contests map to a global **13+** rating on current OS versions. [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- **Gambling:** answer **No** only while there is no real/in-game money, entry fee, wager, pot, payout, or prize. Private skill-based Steps challenges are not gambling under Apple’s definition. Keep “bet” and settlement language out of the binary and metadata. [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- **Contest rules:** a simple in-app rules/terms page stating no fee, prize, wagering, medical claim, or Apple sponsorship is **recommended** to reduce ambiguity. If Apple applies Guideline 5.3 to the private challenges, developer sponsorship, official rules, and the statement that Apple is not involved become required. [Apple Guideline 5.3](https://developer.apple.com/app-store/review/guidelines/)
- **Regulated medical device:** if categorized Health & Fitness and offered in the US, UK, or EU/EEA, complete the required declaration; **No** is the apparent truthful answer because FitFight does not diagnose, prevent, monitor, or treat disease. [Apple regulated-medical-device declaration](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status/)
- **Privacy, support, screenshots, description, category, copyright, review contact/phone, review notes, export compliance, content rights, territories, release method, and DSA status:** complete them against the exact final build. Apple requires accurate metadata and screenshots that show the app in use. [Apple platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) and [required properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)

Apple requires a DSA trader/non-trader declaration even when the app is not distributed in the EU; EU distribution by a trader adds public verified contact information. [Apple DSA guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)

## 7. Verify the submitting entity

Apple says apps in highly regulated fields **or apps that require sensitive user information** should be submitted by the legal entity providing the service, not an individual developer. FitFight requires linked Apple Health data, so confirm the Apple Developer enrollment and seller identity before submission. This is a conditional blocker because the repository cannot reveal the account type. [Apple Guideline 5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/)

## Health-specific correction to the original audit

The original audit treated participant-visible Health-derived totals as needing written Apple confirmation. Apple’s current HealthKit overview expressly names social interactions and a friends’ daily step-count challenge as a HealthKit use case, so written confirmation is **recommended only if Apple raises a case-specific question**, not a general stop-ship gate. [Apple HealthKit overview](https://developer.apple.com/documentation/healthkit/)

The requirements that do remain are:

- access only for an evident health/fitness purpose;
- clearly disclose the specific Health data read and how it is used;
- obtain prior express consent before off-device use/sharing;
- protect the data and use it only for the consented fitness service;
- no advertising, marketing, sale, brokerage, or unrelated mining; and
- respect revocation and deletion. [Apple Health privacy guidance](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [Guidelines 5.1.1–5.1.3](https://developer.apple.com/app-store/review/guidelines/), and [Apple Developer Program License Agreement, HealthKit section](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)

The current Connect row and Health usage string disclose upload and participant-visible totals, and the upload is aggregate-only. That is a strong base. The final gate is to deploy the linked policy, make sure the user’s tap is the express choice to upload/share, and test allow, deny, limited-history, revocation, and deletion on the production candidate. Apple recommends requesting Health access in context rather than on launch and managing Health permission through Apple’s system settings. [Apple HealthKit HIG](https://developer.apple.com/design/human-interface-guidelines/healthkit/)

## Explicitly not blockers

- **Push notifications:** not required. Apple says they must not be required for functionality and must not carry sensitive/confidential information. Do not add them solely for review. [Apple Guideline 4.5.4](https://developer.apple.com/app-store/review/guidelines/)
- **Payments or IAP:** not required because the current app sells no digital goods or services.
- **Sign in with Apple itself:** using it as the only login is acceptable. The remaining issue is review access and revocation during deletion, not the login provider.
- **More features:** not needed. Adding social feeds, chat, more metrics, money, or notifications would increase review surface and risk.

## Practical submission gate

Do not submit until all seven ranked items are closed or explicitly verified. The shortest safe sequence is:

1. UGC filter/report/block plus moderation operations.
2. Complete deletion and Sign in with Apple revocation.
3. Deploy Privacy/Support and reconcile the privacy manifest/label.
4. Build the reviewer-access path and production candidate.
5. Complete a two-account real-device pass.
6. Fill App Store Connect accurately and submit with precise Review Notes.
