# HTTP API

v1 is REST + JSON, `/v1`. Bearer access token. Every GET includes `"server_time"` so the phone can store clock offset. ETags on GETs. Silent push is a **scope**, never a score.

Auth: [`../security.md`](../security.md). Outbox + score batches: [`../sync.md`](../sync.md).

## Resources

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/v1/auth/apple` | Identity token + nonce. Mint our session. |
| POST | `/v1/auth/refresh` | Rotate refresh. |
| POST | `/v1/auth/logout` | This device. |
| DELETE | `/v1/me` | Account delete (required before store review). |
| GET | `/v1/me/export` | GDPR dump, JSON. |
| GET | `/v1/me` | Profile. ETag `me`. |
| GET | `/v1/fights` | Summaries. Weak ETag `fights`. |
| GET | `/v1/fights/:id` | Members, score days, optional `display`, settlement if frozen. |
| POST | `/v1/commands` | Array of `{id, type, body}`. Idempotent on `id`. |
| POST | `/v1/score-batches` | One fight. Daily integers. |
| POST | `/v1/devices/push-token` | APNs token for this session. |
| GET | `/v1/requests` | Feedback tab. |
| POST | `/v1/fights/join` | Body `{ code }` rate-limited. |

Command types v1: `create_fight`, `accept_invite`, `decline_invite`, `vote`, `unvote`. The clock starts when the server applies create, not when the phone queued it.

## Score batch

```json
{
  "fight_id": "…",
  "compiled_at": "2026-08-23T21:10:00Z",
  "time_zone": "Europe/Paris",
  "source": "healthkit",
  "fingerprint": "hkstat:v1:stepCount",
  "days": [{ "day": "2026-08-22", "value": 11002 }]
}
```

`Idempotency-Key: scores:{user}:{fight}:{from}:{to}:{sha256}`. Timeout retries the **same** key. After freeze: `409 window_frozen`.

`display` on GET is optional formatted copy. Settlement payload is the only frozen money.

## Push

```json
{ "scope": "fight", "id": "…" }
{ "scope": "fights" }
{ "scope": "requests" }
```

Visible copy: invite / “open so we can sync.” No steps, no dollars on the lock screen.

## Client must not send

Rank, pot, `projectedNet`, settlement, other people’s scores, days outside the window, future fight-tz days, a timezone change, client-chosen ids/codes/`sub`, raw samples, Strava tokens, zeros that mean “query failed.”

| Status | When |
| --- | --- |
| 401 | Refresh. Pause outbox, do not drop it. |
| 409 `window_frozen` | Stop compiling that fight. |
| 409 `duplicate` | Command already applied; return `resource_id`. |
| 429 | Honor `Retry-After`. |
| 422 | Invite expired / fight full → revert optimistic row. |
