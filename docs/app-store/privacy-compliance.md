# App Store privacy and compliance answers

These answers describe the current Steps-only product. Reconcile them against the exact production archive, Supabase and Vercel retention settings, and the published policy immediately before submission.

**Submitted App Store 1.0 (`main`) is Steps-only.** Staging TestFlight from Apple ingest v2 asks for additional HealthKit types listed on the staging privacy page. Do not copy those staging types into the already-submitted App Privacy form unless Marc asks to resubmit.

## App Privacy

Select **No** for tracking. No data type is used for third-party advertising, developer advertising, data brokerage, or tracking across other companies' apps or websites.

Declare these collected data types:

| App Privacy type | What FitFight collects | Linked to the user | Purpose |
| --- | --- | ---: | --- |
| Health | Apple Health Step Count totals for exact Fight windows and relevant daily chart totals | Yes | App Functionality |
| Name | Name supplied by Sign in with Apple, when available | Yes | App Functionality |
| Email Address | Apple email or private-relay email | Yes | App Functionality |
| User ID | Apple subject, Supabase account ID, and FitFight username | Yes | App Functionality |
| Gameplay Content | Fights, invitations, membership state, standings, scores, and results | Yes | App Functionality |
| Other User Content | The action entered for a Fight | Yes | App Functionality |
| Customer Support | Email and message content sent to support | Yes | App Functionality |
| Other Data Types | Time zone and limited request metadata such as IP address | Yes | App Functionality |
| Other Diagnostic Data | Limited server error details used to keep the service working and secure | Yes | App Functionality |

Do **not** declare Contacts: FitFight does not read the address book and no longer stores a friends graph. Also do not declare location, purchases, financial information, browsing history, search history, advertising data, photos, videos, audio, crash analytics, or product-interaction analytics unless the final binary or a production processor adds them.

The launch privacy manifest covers Health, Name, Email Address, User ID, Gameplay Content, Other User Content, Customer Support, Other Data Types, Other Diagnostic Data, no tracking, and the `CA92.1` UserDefaults reason. Before submission, make the exact archive's privacy report, App Store answers, published policy, and manifest agree.

## Age rating

Use these questionnaire answers:

| Question | Answer |
| --- | --- |
| User-Generated Content | Yes — usernames and Fight actions |
| Contests | Frequent — recurring fitness rankings and winners |
| Gambling | No |
| Simulated Gambling | No |
| Messaging and Chat | No |
| Unrestricted Web Access | No |
| Medical or Treatment Information | No |
| Advertising | No |
| Violence, sexual content, profanity, drugs, alcohol, tobacco, horror, or mature themes | None |
| Made for Kids | No |

Apple calculates the final rating. With Frequent Contests, the expected result is **13+**; do not manually choose a lower answer to change the result.

## Other compliance fields

| Field | Answer |
| --- | --- |
| Regulated medical device | No — FitFight does not diagnose, prevent, monitor, or treat disease |
| HealthKit | Read-only Step Count for private fitness competition; no Health writes |
| In-app purchases | None |
| Gambling, entry fees, money settlement, payouts, or prizes | None |
| Advertising / IDFA | None; the app does not request tracking permission |
| Non-exempt encryption | No; `ITSAppUsesNonExemptEncryption` is `NO` and the app uses ordinary platform HTTPS/TLS. Recheck the final archive. |
| Third-party content rights | No streamed third-party content. Nunito is bundled under the SIL Open Font License; SF Symbols are used under Apple's platform terms. |
| Sign-in | Sign in with Apple only |
| Account deletion | Available in the app under You → Settings → Delete account |
| Privacy URL | `https://fitfight.app/privacy` |
| Support URL | `https://fitfight.app/support` |

Marc must personally confirm the legal/account answers that code cannot determine:

- Individual versus Organization seller enrollment and the correct legal entity.
- DSA trader or non-trader status and any required verified public contact details.
- First-launch countries and regions. A United States-only first release is the smallest compliance surface, but this is a business decision.
- The international App Review contact phone number.
- Whether export documentation is needed for every selected territory, including France.

Do not submit until the production Privacy and Support URLs return `200`, the production backend is live, and every statement above matches the selected binary.
