# Identity, invites, graph

One human, one `auth.users` row, one `profiles` row. Apple is the only login.

## Sign in

iOS: `AuthenticationServices` → nonce → `signInWithIdToken(.apple)`. Write `fullName` **the first time Apple sends it** (once per credential).

No session → Sign in. Session but no handle → claim handle. Then tabs.

Web later: same Apple Services ID, same `sub`. Invite pages do not mint sessions via magic links. Token in the URL is an **invite**, not a password.

Account deletion is in-app the day accounts exist (Apple 5.1.1(v)).

## Profiles

`auth.users` is Auth. Product reads `profiles`.

Handle: 3–20, `^[a-z][a-z0-9._]{2,19}$`, stored without `@`. RPC `claim_handle` (reserved list, uniqueness, 90-day cooldown). Reserved: `marc`, `fitfight`, `support`, `admin`, `help`, `official`, `you`, `fights`, …

`@marc` is staff (`role = staff`), looked up by role, not a hardcoded UUID in the client.

Avatars: Storage `{user_id}/…`. Apple has no photo.

Email (often private relay) never appears on cards.

## Invites

Do not create ghost profiles for people who do not have the app.

| Id | Role |
| --- | --- |
| `FIGHT-XXXXXX` | Label, guessable, not a credential |
| Invite token | 128-bit, URL `/i/{token}`, preview only |

Share: `https://fitfight.app/i/{token}`. Landing: inviter, name, metric, length, bragging vs money-exists. **No scores.** Open in app / App Store.

App stashes token if onboarding is incomplete, then `POST /api/v1/invites/:token/claim`. Join requires a session.

New-fight roster v1:

- People you already share a fight with (minus blocks)
- Handle search (prefix, not a global directory)
- Share link after create

No `friendships` table. Pokes (later) use fight roster + handle search.

## Graph

**The fight is the graph.** Membership is the social object. Follows/DMs later, not now.

Blocks (from day one, Requests is already UGC): hide roster/search, cannot invite, live fights stay (the contract stands) but no poke/profile. Reports insert-only, staff reads.

## Deep links

Associated Domains `applinks:fitfight.app`. AASA from Vercel.

| Path | After auth |
| --- | --- |
| `/i/{token}` | claim → fight |
| `/f/{code}` | open if member, else “ask for an invite” (AASA includes `/f/*`) |
| `/s/{sticker}` | later, campaign only |

No `?access_token=` in URLs.

## Deletion

RPC `delete_my_account` on Vercel/service role. Phone never holds service role. Tombstone `profiles` first (`deleted_at`). FK is `ON DELETE RESTRICT` — do not cascade-wipe the profile when Auth is removed. Disable/delete Auth after samples are gone; keep the tombstone row.

| Data | Fate |
| --- | --- |
| Auth, email, Apple sub, tokens, avatar | Hard delete |
| Raw samples, ingest | Hard delete |
| Profile | Tombstone: “Deleted user”, handle released after 90 days |
| Finished settlements | Keep (opponent’s receipt) |
| Live membership | Forfeit / drop per settle rules |
| Requests text | Keep, author tombstone |

Reinstall + same Apple ID is a **new** user id. Handle reclaim after the hold. Deletion is not undo.
