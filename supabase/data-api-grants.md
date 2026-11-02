# Data API grants

On 30 Oct 2026 Supabase stops granting `anon`, `authenticated`, and `service_role` on new tables, views, sequences, and functions in `public`. A new object is not reachable through the Data API until a migration grants it. Existing grants stay. Direct SQL as the database owner is unchanged. `private` is not in the Data API schemas.

When a migration creates a table, view, or sequence in `public`, grant only the roles that use it:

- `service_role` for the server's Supabase client (`createAdminClient`).
- `authenticated` for the operations its policies allow, or that an installed client still calls.
- `anon` only for a real signed-out read or write. FitFight has none.
- `usage, select` on a sequence when that role inserts into an identity or serial column.

Put the `GRANT` in the same migration, or in a later one. Policies stay as they are. A grant does not replace a policy.

To create a public object that must stay off the Data API, add this comment in the migration that creates it:

```sql
-- data-api-grants: opt-out public.example
```

`scripts/check-data-api-grants.py` fails the database check when a public object has neither a later `GRANT` nor that comment. The grant has to be a top-level statement. A grant inside a `do` block does not count.
