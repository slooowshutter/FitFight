# Settlement and money

Not legal advice. v1 is a **private challenge tracker** that writes an **IOU**. It is not a wallet, sportsbook, or money transmitter.

Copy already on New: *“Scores sync automatically. You settle up at the end.”*

Store listing: challenge, stake, buy-in, settle up. Avoid: bet, wager, odds, casino, cash out.

## Axioms

1. One function `settle()` for live projection and freeze.
2. Money is integer cents. `sum(net_cents) = 0` over committed members.
3. Invited people are not in the pot.
4. Samples in `[starts_at, ends_at)` count. Uploads may arrive until freeze.
5. Bragging writes no obligations. Action writes text, `amount_cents = 0`. Never mix in one row.
6. Phone displays. Server freezes.

## Stake (immutable after create)

| Kind | Fields | Modes |
| --- | --- | --- |
| bragging | buy-in 0 | none |
| money | `buy_in_cents` 500–10000, USD | winner, proportional, goal |
| action | `forfeit_text` | winner, goal. **Server rejects proportional** |

## Committed set

`C` = accepted members. `n = |C|`. `pot = n * buy_in` (money).

List-card pot is this number. Pending invites are a badge, not dollars.

Accept until `ends_at`. After start, no leave (v1). If `n < 2` at freeze → cancel, no IOUs.

Late join: full window, no discounted buy-in. Health history in-window counts.

## Scores

After canonical sessions. Never-synced accepted member: **0**, still in `C`, can lose. Void **only** if nobody in `C` has a qualifying sync (opening the app and uploading an empty snapshot counts as a sync).

## Modes (algorithm_version = 1)

Hamilton largest-remainder for splits. Ties: higher score, then `user_id`.

### Winner + money

Unique first takes pot (`net = pot - buy_in`). Ties at first split pot. All equal (including real all-zero **with** syncs): nets 0.

### Winner + action

At most one debtor and one creditor: unique last owes unique first. Any tie at first or last → no obligation (ranking still freezes). Not “everyone buys dinner.”

### Proportional + money

`payout_i = Hamilton(pot, score_i)`, `net = payout - buy_in`. All-zero scores: nets 0.

### Goal + money

Hit iff `score >= daily_goal * length_days` (window quota, not every calendar day). Missers forfeit buy-in; hitters split the forfeit pool. All hit or all miss → nets 0.

Live **SAFE / AT RISK** is that test on **projected** score.

### Goal + action

Each misser owes `forfeit_text` once to the unique highest hitter. Tie among hitters for first → void action.

## Live projection

While `now < ends_at`:

```
elapsed_days = max(1, days from start through fight-local today)
projected_score = score * length_days / elapsed_days
```

Linear hold-pace. After `ends_at`, factor = 1 (grace only waits for uploads).

Header “If it ends like this you’re …” = sum of **live+settling** nets, round **once** at the end, not the sum of per-card rounded dollars.

Do not persist live nets as truth.

## Freeze

States: `scheduled → live → settling → settled` (or `cancelled`).

1. Lock fight. If already settled, return snapshot.
2. Recompute from samples in window.
3. Expire leftover invites.
4. `n < 2` → cancel.
5. `settle()`.
6. Write `fight_settlements` + lines + pairwise obligations (greedy: largest debtor to largest creditor).
7. Status settled. Late in-window samples after freeze may still be stored with `excluded_reason = 'late'`; they do **not** change nets.

Idempotent on `fight_id`. `algorithm_version` stays on the row when we later change maths.

## Ledger

No pooled cash. `obligations` are who owes whom **per fight**. No cross-fight netting as source of truth.

Paid acknowledgement (API only until a screen exists): payer may mark; **payee confirm** closes. Never infer paid from Venmo.

Company credits later: **other tables**. Credits never pay a friend IOU and never cash out in-app.

## Anti-cheat

v1 trusts HealthKit/Strava. Store source + external id + timestamps. Do not add `anomaly_flags` until anti-cheat is a real project. Do not let a loser void by accusing. Faking is an accepted v1 stance.

## Fixture math that is wrong

Implement the spec, not the sloppy mock arithmetic:

- Pot must move when someone accepts (mock Step Derby $50 with an invited fifth).
- Invited people have **no** net.
- Goal 2-hit 2-miss at $20 is +20/+20/−20/−20, not +7.
- Empty scores among two accepted people: even, not “creator wins the fantasy pot.”
