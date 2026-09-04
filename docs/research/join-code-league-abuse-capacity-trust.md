# Join-code league: abuse, capacity, and trust

**4 Sep 2026.** Not a build. Product decision: [`proposals/themed-recurring-fights.md`](../proposals/themed-recurring-fights.md). This page is caps, hashing, and failure modes for a shareable join-code Steps league on top of today’s private username Fights, device-trusted HealthKit uploads, and a public GitHub repo.

Anyone with the code can join. The generator will be visible. Security is entropy, hashing, caps, and rate limits, not obscurity.

## Failure modes and minimum controls

**Code stuffing / enumeration.** Length and alphabet will be public. Store only a hash (same as current 32-byte fight invite tokens). CSPRNG **8 Crockford-base32** chars (~10¹²). Same error for invalid, expired, revoked. Join tries: **10 / User / hour**, **30 / IP / hour**. Organizer can rotate. No sequential IDs or 4-digit PINs.

**Spam dump.** A leaked Slack code becomes a username landfill. Cap **50**; freeze at cap; organizer **kick + rotate**. No chat, bios, or posts. Usernames and a typed loser action are still UGC. Apple 1.2 (filter, report, block, contact) already applies to today’s Fights and is stricter once a code is shareable. No public league directory.

**10k joiners melt standings and Health sync.** One User’s upload stays one small aggregate POST, but N members × standings reads, chart days, and a 9am open-the-app wave will melt. Hard cap **50**. Paginate standings. Coalesce HealthKit writes (**1 successful write / User / minute**). Reject create/join past caps. Do not design for 10k.

**Duplicate accounts (two Apple IDs).** One person, two Apple IDs = two Users. Hide My Email makes this easy. FitFight cannot bind a human. Policy: one Apple ID, one User. Organizer kicks the extra. No device fingerprints or phone numbers.

**Organizer gone / hostile.** Today, account deletion **deletes owned Fights**. That must not cascade-delete a live league. Apple also forbids making Delete account hard, so deletion always succeeds. v1: live league is **orphaned** (joins frozen, scoring continues, owner PII and score stripped). Hostile owner may kick and rotate; may **not** change the window or rules after start. No multi-admin.

**Screenshot harassment.** iOS cannot stop screenshots. No share-image generator, no public leaderboard URL. Copy: members only. Watermarks crop. No screenshot-blocking APIs.

**HealthKit spoofing (good-enough).** The server already trusts the signed-in device’s Apple merged aggregate. Step-faker apps, manual Health entries, and a scripted JWT client all win. Good-enough: own-data only, reject nonsense (**>150k steps / day**; today’s schema allows Int32 max), show last sync, organizer kick. Do not collect source or device metadata “for fraud.”

**Join then scrape the member list.** Membership is the directory. No Apple IDs, emails, or needless UUIDs. Paginate; no CSV. Rate-limit list reads. Today any signed-in User can select all non-deleted `profiles`; that must not become the league directory.

**Lurk without Health.** Seeing everyone else’s ranks without reciprocating is the failure. Join completes only after Apple Health is connected (authorized; preferably one successful sync). No spectator role.

**Account deletion in a live league.** Member: strip score and handle; standings recompute; show absence, not their name. Owner: orphan as above. Never block Delete account.

**iOS-only / Android exclusion.** HealthKit plus native Sign in with Apple means an iPhone. An Android user cannot mint HealthKit scores without an iPhone (or a stolen session plus a raw API client). That is exclusion, not an Android spoofing attack. Say **iPhone required** on the landing page. Do not build Health Connect or fake-iOS detectors.

## v1 hard caps

**50** members (warn at 40). **3** live leagues organized per User, **10** joined. Join tries 10 / User / h and 30 / IP / h. Code regen 5 / day; creates 3 / day. HealthKit: 1 accepted write / User / minute, coalesced. Code: 8-char Crockford-32, hashed, rotatable.

## Must-have / nice-to-have / should-nots

**Must-have:** hashed high-entropy codes and join rate limits; member / organize / join caps; freeze at cap; organizer kick + rotate; Health connected before join; own-data uploads with a plausible daily ceiling; deletion never wipes a live league or keeps PII; no public league index; iPhone-required copy; report / block / filter / contact if the code is shareable.

**Nice-to-have:** join-approval queue; second organizer; viewer-name watermark; join pause without rotating; audit log of kicks and rotates.

**Should-nots (no anti-cheat lab):** device fingerprinting; raw HealthKit samples or `HKSource` provenance to catch cheaters; ML fake-step detectors; screenshot DRM; phone-number KYC; “secret” sequential codes; spectator mode; 10k-scale standings; Android spoofing defense.

## Quirks

Treat the generator as known. Same Apple ID on staging vs production is already two accounts. Manual steps in Apple Health count. A borrowed iPhone is a real User. Current owned-Fight deletion would be wrong for a league.

## Marc questions

1. v1 = **shareable-join Fight** (one window) or a **durable community** that hosts many Fights?
2. Cap **50**, or smaller (office ~20 / class ~35)?
3. **Kick** only, or also a join-approval queue?
4. Organizer deletes mid-league: **orphan until the window ends** (recommended) or **cancel**?
5. Health connected **before join**, or join now and sync later (lurkers)?
6. Ship **report/block** with the first join-code, or treat the code like a group chat and accept Apple 1.2 risk?
7. Typed loser action still required at 50 people, or private-Fight-only?
