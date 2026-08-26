# FitFight API (Next.js)

iOS command API only. No marketing pages. Node.js runtime, never Edge.

## Marc — Vercel

1. Create a Vercel project on this GitHub repo.
2. Set **Root Directory** to `web/`.
3. Env vars (Vercel dashboard only — never paste secrets in git or chat):

| Vercel env | Preview + `develop` | Production (`main`) |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase **develop** project URL | Main / production project URL |
| `SUPABASE_SECRET_KEY` | develop secret key | production secret key |
| `FITFIGHT_APP_URL` | staging site origin (optional) | production site origin (optional) |

Preview deployments must use the **develop** Supabase project. Never point Preview at production.

The Data API must include the `private` schema so this server can write `private.metric_observations`. Clients have no table grants on that schema.

After a `web/` push, Vercel deploys. iOS uses the User JWT as `Authorization: Bearer <jwt>`.

## Local

```bash
cp .env.example .env.local
# fill URL + secret from the develop project
npm install
npm run dev
```

- `GET /api/health` → `{ "ok": true }`
- Commands live under `/api/v1/...` (see `contracts/openapi.yaml`)

```bash
npm run typecheck
npm test
```
