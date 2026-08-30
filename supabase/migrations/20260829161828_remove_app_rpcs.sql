-- Swift calls authenticated Next.js routes. No application mutation is exposed
-- as a PostgREST RPC; TypeScript owns authorization and database transactions.

drop function if exists public.ingest_healthkit_steps(jsonb);
drop function if exists public.delete_own_account();

revoke all on function public.handle_new_user() from public, anon, authenticated;

revoke all
  on private.healthkit_step_samples,
     private.healthkit_step_sample_deletions,
     private.healthkit_step_source_days,
     private.healthkit_step_syncs
  from public, anon, authenticated;
