# Roadmap — what to build, what not to fake

The screens stay fixtures until the stack under them exists. Do not sneak `URLSession` into `FightsListView`.

## Now (unblocks “real fights”)

1. **This design** (this PR).
2. **Identity + API shell** — SIWA, sessions, empty fight list. Marc: capability + privacy policy URL.
3. **GRDB replica + commands outbox** — create / accept / vote survive a kill. Still fake scores if needed.
4. **HealthKit compiler + score outbox** — daily totals, fight TZ calendar, no zeros on failure.
5. **Settle job + grace noon + “open to sync” push.**

Then the Fights tab can drop Leo.

## Next (still v1)

- Recurring: insert the next `fights` row from `series.template`. Do not mutate the old window.
- Requests tab against `feedback.*` (no compose/thread UI until designed).
- Block / report APIs before any poke copy ships.

## Later (hooks exist, product does not)

| Idea | Hook | Do not |
| --- | --- | --- |
| Dual vs backers | `shape = dual`, roles, mass checkpoints | JSON blob on `Fight` |
| Company credits | `orgs` + `stake_kind = credit` | Mix credits into USD pot |
| Stickers / QR | `public_code` / join token | `fights.qr_url` |
| Pokes | `social.pokes` + Safety rules | Health or money on the lock screen |
| Watch complication | Read-only from cache | Second compiler |
| Per-person goals | `memberships.daily_goal_milli` | Invent the create UI |

## Explicitly later-or-never

Payment rails, IAP pots, public matchmaking, friend graph, Android, websocket leaderboards, anti-cheat ML, storing raw samples “for disputes,” certificate pinning.

## Capabilities Marc must flip (when that code PR exists)

Sign in with Apple · HealthKit · Push · (background delivery entitlement). Privacy policy hosted. APNs + SIWA keys as GitHub **server** secrets, never in the app.

Until then: no TestFlight behavior change from this docs PR.
