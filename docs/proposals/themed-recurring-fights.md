# Themed / recurring fights (Station F and the weekly rematch)

Status: **proposal. Do not build. No screens.**

Marc asked: a recurrent fight for a place like Station F — admin? join with code? how?

**This is three products.** Do not ship them as one toggle on today’s Fight.

| | Rematch | Code on one Fight | Community (Station F) |
|---|---|---|---|
| Who | People you already know | Same, plus “here is the code” | A place. Roster churns. |
| Lives how long | One window, then maybe another | One window | The group outlives any week |
| Join | Exact username, as now | Code / QR into **that** window | Code into the **group**; each week is a new Fight |
| Admin | Fight owner, as now | Same | Organizer of the group, not FitFight staff |
| After App Store | First | Second, if still needed | Ask first — needs Marc’s answers below |

Private Fights stay Steps × highest total, required loser action, 3/7/14/30 days. A campus league that copies that recipe will feel like PE class.

Clock details: [`recurrence.md`](../recurrence.md). Abuse / caps: [`research/join-code-league-abuse-capacity-trust.md`](../research/join-code-league-abuse-capacity-trust.md).

---

## The product bet

FitFight stays a private Steps fight. Station F is not a theme. It is a **Community**: a durable roster with a join code that **hosts** ordinary Fights. Each week is a new Fight. Never one immortal Fight whose scores reset.

Wife / roommate weekly is a **Fight series**: same named people, server (or Redo) mints the next window. No code. No campus identity.

A parallel note ([#75](https://github.com/slooowshutter/FitFight/pull/75)) treats Station F as “Series + join code,” same object as the wife week. That under-builds roster churn, scoring, and consent. Same clocks. Different join, stake, and privacy.

---

## Why Station F is a different problem

A weekly fight with one person assumes a stable roster, exact usernames, a typed dare, and highest-total as the joke.

Station F is a campus of many companies, visitors, and alumni. People know Slack names and badges, not FitFight handles. The poster / QR **will leak**. Half the building is Android. “The loser does X” among 80 people is public last-place. An organizer dashboard is a health export. French labor / GDPR treat Steps as health data; a founder “making the team join” is not the same consent as two friends.

Call it a **themed public-ish league that shares a building**, not workplace wellness. Workplace wellness is one employer and a gradebook. That is the parked school / company-culture items, and those still must not grow a spy dashboard.

iPhone + Apple Health is a club. Say so. Do not call it campus-wide until Android exists.

---

## Objects (keep today’s language)

Keep **User, Fight, Fight member, Fight owner, Invite, Fight window, Stake, Final result**.

Add only when we build them:

- **Fight series** — template + named roster + cadence. Each period is a new Fight. Series owner is the same idea as Fight owner: not staff, no extra Health.
- **Community** — name, organizer, roster, join materials, series settings. Not a Fight. No live standings on the Community itself.
- **Join code** — human thing people can say (`STATIONF`) plus an opaque hashed Universal Link / QR. The short code is convenience, not a secret. Rotate kills the code; the roster stays.

Do not add FitFight **staff**, **Admin**, **League**, **Group** as product words. Do not add employer / HR accounts.

---

## Build order (after the App Store two-phone Fight actually works)

Now / Next stays: staging Health, a real 3-day close, then App Store when Marc says. Recurrence multiplies bugs we have not seen yet.

1. **Manual Replay** on a finished private Fight. Copy rules and roster. People accept the new window. Smallest proof anyone wants “again.”
2. **Auto series** for that same named roster. Server mints the next Fight at `ends_at` (not when everyone has synced). Tiny win/loss count from `final` rows.
3. **Join code into one live Fight** — only if we still need “I don’t know their username” before we need a durable group.
4. **Community + code + rolling periods** — Station F. Each period is a normal Fight for whoever is in the group *then*.
5. **Organizer tools** — rotate code, remove from *future* weeks, pause the series, transfer organizer. Meaningless before 4.
6. **“Did you do enough”** — school / company reporting. Same Community object, different Result rule. Still not a spy feed.
7. **FitFight-seeded official leagues** — last, or never. That is us as commissioner.

Replay unlocks auto-series. Join codes unlock growth. Community is the Station F product.

---

## Rematch (wife) — must / nice / don’t

**Must**

- Next week is a **new Fight**. Do not reopen `final`, slide `ends_at`, or reset scores on one row.
- Same shared window for every member. Late accept still means full-window credit from Apple Health — so the roster is the people already invited, not a hallway code.
- Server (or Redo) creates the child. The phone does not insert “next week” by itself.
- Rules / loser action lock per Fight. Edits apply to **future** windows only.
- Past Finals stay frozen (same freeze-history rule as the rest of the backlog).

**Nice**

- Tiny series ranking: how many times each person won.
- Pause / skip a week without erasing history.
- Leave the series without deleting past Fights.

**Don’t**

- One year-long Fight.
- Join codes on a private two-person Fight.
- Wait for HealthKit to finalize before minting next week.
- Treat rolling “1 week from now” and “calendar Monday–Monday” as the same duration.

Wife default: **Replay**. Auto-roll later if they still forget to tap. Keep the start weekday/time; do not snap a couple onto Paris Monday.

---

## Community (Station F) — must / nice / don’t

**Must**

- Join without knowing usernames: typed code on **New**, plus Universal Link / QR to the same confirm. Signed-out path: Welcome → Apple → username → resume. No anonymous Fight members.
- Joining the Community is **not** Fight acceptance. Sharing this week’s Steps needs a second confirm (or a standing-share sentence that is impossible to miss).
- Default: new people start **next period**. Same-week entry only inside a short cutoff. After cutoff, do not backfill four days of Watch history onto a live board.
- Health connected before they see other people’s standings. No spectator.
- Organizer is a member of **that** Community. They see what any member sees: usernames, this week’s standings, the code. They do **not** see emails, Apple IDs, raw history, sources, or a CSV of scores.
- Transfer organizer to another member. If the last organizer deletes their account: **pause** future weeks; the live Fight still finishes. Do not cascade-delete other people’s history (today, deleting an owned Fight would be wrong here).
- Remove from **future** weeks + rotate the code. Do not kick mid-window (voids the week, looks like HR).
- Pause / end the series without cancelling the live Fight.
- Cap **50** people. Freeze at cap. This is a table, not a stadium.
- Report / block / filter / contact **before** the first shareable code (Apple 1.2). Support page alone is not enough once a QR exists.
- Privacy copy names the join-code audience, that weekends are visible from weekly totals, that this is not for work evaluation, and how to leave.
- iPhone required, said out loud.
- Still three tabs. **Join** is a fork on **New** (private Fight vs code). The Community is **one card** on Fights that updates each week. Past weeks live inside that card. No fourth tab, no web admin, no public directory.
- A code Community may start with the organizer alone. Today’s “at least one invitee” is a 1:1 fossil.
- Leave / rage-quit stops **future** weeks. The current Fight row stays (`withdrawn`). Deleting the account must not erase a loss or wipe other people’s history.
- Daily charts on a 30-person board are a sick-day / weekend tracker. Default the large board to window total + rank. Keep the day chart on **your** row.

**Nice**

- Human alias (`STATIONF`) on top of a hashed opaque token. Owner rotates; old **poster dies** — rotation is rare and loud, not a weekly PIN.
- Guest vs standing member (tourist QR, intern who left the country).
- Pre-mint the **next** period as `scheduled` so Monday is never a surprise.
- Opt out of next week without leaving the Community.
- Second organizer.
- Season of N weeks, then stop (forgotten always-on keeps querying HealthKit).
- Table teams later.
- Series win/loss tally on that same card.

**Don’t**

- FitFight staff console, verified-organizer KYC, or “official Station F league” badge.
- Employer / HR / teacher accounts. No “did they do enough” export to a boss.
- CSV of members **and** scores. Usernames for kick is the ceiling.
- Public leaderboard URL, TV in the hall, share-image of last place.
- Email-domain allowlist (`@stationf.co`) — Hide My Email, Gmail, visitors.
- Auto-add from Slack or a badge list.
- Required participation as a product flag.
- Money, credits, pots.
- Chat, feed, bios.
- Mid-Fight rewrite of duration or action.
- Anti-cheat lab (fingerprints, raw HealthKit samples, ML fake-steps). Good enough: cap, kick, nonsense ceiling, visible incomplete sync.
- Android fake-iOS detectors. They cannot score without an iPhone.
- Restoring friends, Requests, or Discover.

---

## Scoring and stakes (this is the PE-class trap)

Today: **most steps wins**, and the last person has a typed action. Fine for two friends. Brutal at 30+.

For a campus Community, recommended default **if Marc reopens scoring**:

- Still **Steps** (no Active Minutes, no workouts).
- Score = **days reaching** a shared bar (8,000 is the campus guess).
- Result = **Reach** (enough days this week), not a 80-person highest-total board.
- Lead the UI with enough / not enough. Incomplete sync is not “you came last.”

That combo already exists in [`fight-rules.md`](../fight-rules.md). It is **not** production. Shipping it is a scope reopen, not a Station F skin.

Loser action: **keep required for private Fights**. For a Community, make it **optional shared ritual copy** (a mug, a joke). Empty is the intended default. The product must not assign last place a forfeit. People will still screenshot the bottom of the list — do not help with a share card.

Highest-total can stay as an optional Community mode later. It must not be the campus default.

---

## Clocks (the quirk that breaks leagues)

A Fight window stays `[starts_at, ends_at)`. Late HealthKit during grace is a **sync tail**, not extra scoring.

**Do not mint the next week when the previous one finalizes.** Grace would delay Monday; a stuck upload would skip the league. Mint at `ends_at`. Unique `(series_id, starts_at)`. At the boundary: this week → `awaiting_final_sync`, next week → `live`. An event at `ends_at` belongs only to the next Fight.

**Wife “1 week”** today is rolling from create time. **Station F weekly** is a civil week in the venue zone (`Europe/Paris`, Monday 00:00 unless Marc picks 09:00). DST weeks are 167h or 169h. Do not add 168 hours to UTC.

One series, two live scoring windows that overlap = the same steps count twice. Abutting windows plus grace is not overlap.

---

## Join path

1. Exact username — keep for private Fights.
2. Opaque invite token / Universal Link — keep for named invites (`/invite/...`).
3. Community: human code **and** `https://fitfight.app/join/<opaque-token>`. QR encodes the HTTPS URL, never the health data.
4. Approval queue — later, off by default.
5. Email domain — no.

Assume the Slack pin leaks. Rotation is the kill switch, not “please don’t screenshot.”

People will paste the code into the username field. Same box, two jobs, or a clear Join path. “This week’s code” in Slack trains them to rejoin every Monday — they must not. A tourist QR and a shared iPad at a demo both create forever-members unless leave is obvious and guests are not standing members.

---

## Who is “admin”?

v1 of the product still has **no FitFight staff role**. Marc creating Station F is him as a User on his phone, sharing a code in Slack.

| | Fight owner | Community organizer | FitFight staff |
|---|---|---|---|
| Exists | Yes, per window | Yes, per Community, when we build it | **No** |
| Can | Start/cancel **that** window, same as today | Roster, code, pause series, edit **next** template, transfer | — |
| Cannot | Other people’s Health | Other people’s Health, live kick, CSV, extra columns | — |

Hostile or gone organizer: pause joins, live week continues, PII stripped. No spectator-admin who walks zero steps and sees everyone.

---

## Technical seam (when it is time)

Reuse `fights`, `fight_members`, `fight_invites`, the closer cron, HealthKit exact windows.

Add conceptually: Community, membership, join-code (hashed), series settings, `fights.series_id` + period index. Auto-enroll and mint stay in Next.js. No app-facing RPCs. No client “reset this Fight.”

Account deletion must not wipe a live Community the way it currently deletes owned Fights.

---

## Map to the backlog

| Existing item | Relationship |
|---|---|
| Replay and recurring fights | Rematch + auto series. Keep. First to build after App Store. |
| School / university | Community + “enough,” different organizer. Keep separate. |
| Company yearly culture | Same, not a year-long Fight. Keep separate. |
| Company-sponsored credits | A pot. Do not fund Station F with it. |
| Challenge social | A feed. Station F does not need it to exist. |
| Street stickers | QR is the same join path; the sticker is marketing. |
| Notifications / pokes | Still not now. Recurring makes missing finals worse; closer stays open-app + cron. |

---

## Marc — these answers fork the work

Until these are answered, do not invent Groups, Admin, or codes.

1. **Same people, or a place?** Wife → Replay. Station F as a room people enter → Community. Both = two ships, not one toggle.
2. **Does the group outlive the week?** If no, a join code on one Fight is enough. If yes, we are buying a Community object.
3. **Highest total, or “did you do enough”?** Highest is the current product and a PE ranking at campus size. Days-reaching + Reach needs a scoring reopen.
4. **Loser action at N people?** Keep the dare for friends. For a campus: empty / trophy, or it becomes humiliation.
5. **Who operates Station F?** A resident (dies when they leave), you on your phone, or FitFight as official league? Recommend: a resident; transfer; you may create the first one as a User.
6. **Thursday join:** next Monday only (recommended), or this week with Apple Health backfill?
7. **Is this Later, or a launch wedge?** Today’s app cannot run Station F. If there is no campus contact and no appetite for iPhone-only, keep it Later.
8. **Spectator?** Health required to **see** the board (this doc), or belong without Health and race later (#75)? Lurking is the failure mode.
9. **One campus code, or many table codes?** One Station F vs every kitchen/startup. Several Series on one campus is when a Community/Group object actually earns its keep.

Also later, with a lawyer, before any real Station F season: who is the GDPR controller, age gate for leagues vs 13+ listing, season retention after leave/delete, France-from-day-one vs wait.

---

## What “done” looks like when Marc says build

Not this PR. When a slice moves off Later / Ask first:

- Replay: a finished private Fight can start another window; both phones accept; old Final stays frozen.
- Auto series: Monday exists even if nobody opened the app; no double mint.
- Community: a code on New; one updating card; 50-cap; organizer can rotate and pause; no extra Health for the organizer; leave and delete still work.
