# Profiles, friends, rivalry, and suggested fights

Status: product decisions and proposed workflow from Marc's 16 September 2026 discussion. This document does not describe a deployed feature. Core native, API, and database implementation is now prepared on `profiles-friends-and-stats`. Image generation and Terms/sign-in links remain held for the inputs recorded in the implementation plan. See [status.md](../status.md#profiles-friends-and-rivalry-implementation-17-sep-2026) for cloud checks and the separate deployment status.

Implementation sequence, contracts, verification, and rollout: [Profiles, friends, and rivalry implementation plan](profiles-friends-implementation-plan.md).

## Confirmed direction

- You becomes the User's own Profile, with Edit profile at the top right. Other Profiles open as a bottom sheet from avatars and usernames.
- Friendships require mutual acceptance. Another User's Profile offers Add friend and Challenge.
- A Rivalry shows the viewer's record against that User, with a rematch action. It is the strongest addition to the Profile.
- Completion rate is deferred. Show Fights played, Wins, and Win rate; reconsider completion rate only if observed withdrawals make it useful.
- Sign-in shows a Terms and Privacy notice below Sign in with Apple, with tappable links and no separate acceptance step.
- Profile visibility and activity sharing are separate. Private Profiles share their competitive record with accepted friends and current Fight opponents; public Profiles share it with signed-in FitFight Users. Activity history has an explicit metric, period, and audience choice.
- Past opponents keep access to the result of their shared Fight, not continuing access to future private activity. Public Profiles do not publish other members, posts, or Stakes from private Fights.
- Profile opens are measured with viewer, target, entry point, and time. Self-views and duplicate opens do not inflate unique-view counts. Measure the subsequent friend request, acceptance, and shared Fight as well.
- Repeated Profile visits can trigger one image of the pair competing, with both wearing boxing gloves for a competitive 1v1. The same image appears on both Profiles. Marc moved this from a later idea to a candidate for implementation now.
- There is no separate global leaderboard in this proposal. "Everybody on the app" is the name of a Fight selected by Marc.
- Marc chooses suggested Fights. Only public Fights may be suggested. Suggestions also appear at the end of onboarding as joinable invitations, never automatic membership.
- Marc wants administration of those Fights, including stopping them and changing public/private or league behavior. The precise meaning of league behavior still needs definition.

## Two independent Profile controls

Marc agreed to these independent controls. Defaults remain to be specified:

| Control | On | Off |
| --- | --- | --- |
| Competitive | Show the competitive record and eligible Rivalry cards | Hide competitive statistics on the Profile |
| Public | Let any signed-in User view the shared Profile | Restrict the shared Profile to friends and current opponents |

Competitive is presentation, not a different Fight scoring rule. Turning it off must not remove losses, change a shared Fight's standings, or reset the record when it is turned back on. A minimal name/photo/handle remains available where needed to identify an opponent or request a friendship.

Activity-sharing choices remain independent of both controls. Existing private history is not made visible by a new default. The UI explains the audience before joining a Fight and offers a preview of what others see.

## Fights played versus win rate

An ended Fight is not necessarily a win. Playing 10 Fights and winning 3 means 10 played and a 30% win rate.

The current app also has Leave fight, backed by a withdrawn membership state. This is one way to participate without staying to the end. The fight clock ends a Fight automatically after its window and final synchronization period; a User does not press a Finish button. An incomplete final sync is a data-coverage issue and must not be described as a voluntary withdrawal.

Confirmed: show Fights played, Wins, and Win rate prominently. Keep withdrawals and incomplete-data labels in history. Do not add a completion percentage now; revisit it if people leave Fights frequently.

Before implementation, define the treatment of post-start withdrawals, ties, solo Fights, and cancellations. A post-start withdrawal must not improve a win rate. Current scoring can assign rank 1 to everyone when nobody submits complete final data, so rank 1 alone is not sufficient evidence of a win. Rivalry outcomes must use the actual final result and completeness state.

Private and public Fight records can be shown separately. Always retain placement and field size: 12th of 400 and 4th of 4 communicate different performance. A later visibility edit must not silently rewrite historical statistical categories; the point at which a Fight's category is fixed remains a decision for implementation.

## Proposed rivalry-image workflow

The following are implementation recommendations, not already approved parameters:

1. Record an authenticated Profile open only after access succeeds and the Profile is displayed. Do not count prefetches or self-views. Recheck privacy and blocking on every read.
2. Keep raw opens distinct from qualifying repeat visits. Proposed trigger: 10 qualifying visits from the same viewer to the same Profile in 30 days, with at most one qualifying visit per 30-minute window. Repeated refreshes must not generate artwork or charges.
3. Require both Users to have Competitive enabled and permission for the pair artwork to appear. The image cannot reveal a private relationship or private Profile to an audience that could not otherwise see it. Blocking or withdrawing sharing prevents generation and display.
4. Use one unordered pair identity so A viewing B and B viewing A cannot create duplicate jobs. Reserve one generation job for that pair and artwork version atomically when the threshold is crossed.
5. Generate friendly boxing artwork featuring both identities and boxing gloves. Animal companions are the recommended source, but Marc has been asked to choose between companions and illustrated profile photos. No Steps, health history, or visit counts enter the generation prompt.
6. Store one generated asset and reference it from both Profiles. Do not generate two copies. Publish only after the asset is stored and the pair's permissions are checked again. Either participant can hide the shared artwork.
7. Track queued, generating, ready, and failed states. A failure must not publish broken artwork or trigger another paid request on the next view. Deleting an account or revoking sharing removes access to the pair artwork.
8. Link the card to Challenge or Rematch. Keep named visitors and the exact visit trigger internal; the card should not announce that one person repeatedly viewed the other.

Before enabling generation, select the provider/model, per-image spending limit, content policy, and approved artwork inputs. The existing companion selection stores an animal choice or custom description; it is not an operational image-generation pipeline. Existing production AI daily-status generation is recorded as disabled in docs/status.md, and that feature is not evidence of image-generation readiness.

## Suggested Fights and onboarding

The current suggested-Fight list already filters to public, unpaused, joinable Fights. The suggestion mutation checks Marc's admin identity but does not reject a private series. Current onboarding finishes with Bugs & requests and does not show suggested Fights.

Required behavior:

- Reject enabling Suggested on a private Fight at the backend boundary. Hide or disable that action in the native UI with an explanation.
- Making a suggested Fight private removes its suggestion. Making it public again does not silently suggest it again.
- Stopping or cancelling a Fight removes its active invitation. Keep accepted memberships and finalized history consistent with the chosen lifecycle action.
- Use the same eligible suggestions on New and in the final onboarding sheet. Each card shows the real title, participants, rules, timing, shared-data disclosure, and Join action. Users may skip.
- Recheck eligibility when Join is submitted; a Fight can become private, full, or ended while the onboarding sheet is open.
- "Everybody on the app" receives no special hard-coded membership or global-ranking behavior.
- An invitation is an offer to join, not a completed membership. Whether suggestions should also create individual entries in the existing Invitations list remains to be specified.

## Terms notice at sign-in

Marc chose a message below Sign in with Apple with tappable Terms of Service and Privacy Policy links. The current Welcome screen has no Terms or Privacy links, and the public website has Privacy and Support pages but no Terms page.

Agreed sign-in flow and supporting content:

- Show this readable notice immediately below Sign in with Apple: "By continuing, you agree to FitFight's Terms of Service and acknowledge its Privacy Policy." Terms of Service and Privacy Policy are tappable links.
- Users continue through the existing Sign in with Apple flow. Do not add a checkbox, an Agree button, an acceptance screen, or a Terms-acceptance record requirement.
- Returning Users see the same notice when the sign-in screen is shown. Existing signed-in Users do not receive an agreement gate.
- Keep Terms and Privacy permanently available in You settings. Publish readable English and French versions before linking the flow to them.
- Draft Terms around account use, fair play and Fight rules, social conduct and moderation, user content and necessary display rights, informal loser actions, suspension, deletion, fitness limitations, and the service operator/contact. The actual operator, applicable jurisdiction, age policy, and legal wording need legal confirmation before publication. These product recommendations are not finalized legal terms.
- Keep health/history sharing and external AI image processing as separate, specific choices with clear audiences or named recipients and withdrawal controls. The sign-in notice does not enable optional sharing, enroll a User in suggested Fights, or substitute for Apple Health authorization.
- Before Join, summarize the Fight rules and what participants can see. Before external image generation, explain which identity or artwork inputs go to which provider and obtain any necessary permission from both participants. Update Privacy to describe Profile-view measurement, retention, expanded sharing, and the actual generation provider before enabling those behaviors.

Sources checked 16 September 2026: [Apple App Review Guidelines, privacy](https://developer.apple.com/app-store/review/guidelines/#privacy) and [EDPB guidance on lawful processing and consent](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en). Apple requires disclosure and permission for relevant personal-data sharing; where GDPR consent is relied on, it must be freely given, specific, informed, and unambiguous. Agreement to a service contract and permission for optional data uses are distinct.

## Backlog entry ready for Notion

Project: FitFight

Title: Competitive Profiles, friends, rivalry records, and shared boxing artwork

Description: Add independent Competitive and Public Profile controls, mutually accepted friendships, a bottom-sheet Profile, shared Fight history, and a viewer-specific Rivalry with Challenge/Rematch. Show Fights played, Wins, and Win rate; defer completion rate unless withdrawal behavior warrants it. Record Profile opens and the conversion to friendship and Fights. Repeated eligible visits trigger one shared boxing-glove artwork for the pair, displayed on both Profiles under their sharing permissions. Keep activity history under explicit metric/period/audience consent. Use Marc's public suggested Fights, including "Everybody on the app", as optional invitations at the end of onboarding. Show a notice with tappable Terms and Privacy links below Sign in with Apple, with no separate acceptance step. Keep optional sharing choices separate. Do not build a separate global leaderboard.

The implementation plan records working choices for Profile defaults, 1v1 rivalry results, recurrence, artwork identities, visit qualification, win-rate eligibility, and suggested invitations. Image-provider configuration/budget and final Terms facts remain inputs before the relevant features can go live. This conversation is currently in planning scope; no app implementation or deployment has begun.

Notion status: not added. The Notion connector is not installed and no browser is available in this session. This entry is a ready-to-copy capture, not a claim that the shared backlog was updated.

## Verification required when implemented

- Verify all four Competitive/Public combinations and metric-sharing choices, including existing Users who have not opted into expanded sharing.
- Verify the notice appears below Sign in with Apple, both links work before signup, and the flow adds no checkbox, Agree button, acceptance screen, or agreement gate for existing Users. Optional data sharing remains a separate choice.
- Verify friend, current opponent, past opponent, stranger, and blocked-User access. A public Profile must not leak private Fight details.
- Test view deduplication, reverse-pair requests, concurrent threshold crossings, worker failure, and permission changes during generation. At most one paid job per pair/artwork version.
- Verify that both Profiles use the same asset and that neither can expose the other participant beyond the allowed audience.
- Verify withdrawal, ties, incomplete final sync, solo Fights, cancellations, and private/public record classification without rewriting old results.
- Verify that only public eligible Fights can be suggested or joined through onboarding, and that making one private or stopping it removes the invitation.
- Preserve supported mobile contracts. Read docs/shipping.md and live release evidence before API/native-model/schema changes; deploy compatible backend support before distributing the app. Production readiness needs its own evidence.
