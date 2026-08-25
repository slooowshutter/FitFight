# Next

#30 is merged into `develop`. Staging SQL is on. TestFlight **0.9.0 (53)** already uploaded from that merge.

Do **not** merge `develop` → `main`.

## You (Marc)

1. If this chat left a follow-up PR open (fight window / Accept standings), merge it into **`develop`**. Wait for TestFlight.
2. TestFlight → **Update**. Look for `0.9.0 · build N · staging · 26 Aug` (or 25 Aug if you grab 53 before the follow-up lands).
3. Sign in. Pick a **username**.
4. You → Apple Health (allow Steps). Copy your username. Add a friend the same way.
5. New → **3d** → Start fight (alone is fine). Type `@username` on Start if Add friend is fussy.
6. Friends: TestFlight → Internal Testing → their emails. Same build. Their own Apple IDs. Then a 3-day Steps fight.

If sign-in fails: Supabase **develop** → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

No Vercel. No cron. No “expose schema private”.

## After you try it

New conversation. Point it at this file, then [`status.md`](status.md). Proof we want: two phones, standings match, fight shows finished after the days.
