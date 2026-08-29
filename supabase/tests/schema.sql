begin;
select plan(44);

select has_schema('private', 'private schema exists');
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'friendships', 'friendships exists');
select has_table('public', 'fights', 'fights exists');
select has_table('public', 'fight_members', 'fight_members exists');
select has_table('public', 'fight_invites', 'fight_invites exists');
select has_table('public', 'data_sources', 'data_sources exists');
select has_table('public', 'step_days', 'step_days exists');
select has_table('private', 'metric_observations', 'observations stay private');
select has_table('private', 'healthkit_step_samples', 'raw HealthKit step samples stay private');
select has_table('private', 'healthkit_step_sample_deletions', 'HealthKit deletion tombstones stay private');
select has_table('private', 'healthkit_step_source_days', 'source statistics stay private');
select has_table('private', 'healthkit_step_syncs', 'HealthKit sync state stays private');

select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'profiles'),
  'profiles has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'fights'),
  'fights has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'fight_members'),
  'fight_members has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'data_sources'),
  'data_sources has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'metric_observations'),
  'metric_observations has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'step_days'),
  'step_days has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_step_samples'),
  'raw HealthKit samples have RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_step_sample_deletions'),
  'HealthKit deletion tombstones have RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_step_source_days'),
  'HealthKit source statistics have RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_step_syncs'),
  'HealthKit sync state has RLS'
);

select is(
  has_table_privilege('anon', 'public.fights', 'SELECT'),
  false,
  'anon cannot read fights'
);
select is(
  has_table_privilege('anon', 'private.metric_observations', 'SELECT'),
  false,
  'anon cannot read observations'
);
select is(
  has_table_privilege('authenticated', 'private.metric_observations', 'SELECT'),
  false,
  'authenticated cannot read observations'
);
select is(
  has_table_privilege('anon', 'private.healthkit_step_samples', 'SELECT'),
  false,
  'anon cannot read raw HealthKit samples'
);
select is(
  has_table_privilege('authenticated', 'public.fights', 'INSERT'),
  true,
  'clients can insert their own fights'
);
select is(
  has_table_privilege('authenticated', 'public.fights', 'UPDATE'),
  true,
  'clients can update fights they own or that are due'
);
select is(
  has_table_privilege('authenticated', 'public.fight_members', 'UPDATE'),
  true,
  'clients can update their own membership'
);
select is(
  has_table_privilege('authenticated', 'public.data_sources', 'INSERT'),
  true,
  'clients can insert their own sources'
);
select is(
  has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE'),
  true,
  'users can set their handle'
);
select is(
  has_table_privilege('authenticated', 'private.metric_observations', 'INSERT'),
  false,
  'authenticated still cannot write private observations'
);
select is(
  has_column_privilege('authenticated', 'public.fight_invites', 'token_hash', 'SELECT'),
  false,
  'clients cannot read invite token hashes'
);
select is(
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  true,
  'users can update their display name'
);

select ok(
  exists (select 1 from pg_constraint where conname = 'fights_metric_steps_only'),
  'fights are locked to steps'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'metric_observations_metric_steps_only'),
  'observations are locked to steps'
);

select ok(
  to_regprocedure('public.delete_own_account()') is null,
  'account deletion is not exposed as an RPC'
);
select ok(
  to_regprocedure('public.ingest_healthkit_steps(jsonb)') is null,
  'HealthKit ingestion is not exposed as an RPC'
);
select is(
  has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE'),
  false,
  'anon cannot call the signup trigger function'
);
select is(
  has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
  false,
  'authenticated users cannot call the signup trigger function'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_step_samples', 'SELECT'),
  false,
  'authenticated clients cannot read raw HealthKit samples'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_step_samples', 'INSERT'),
  false,
  'authenticated clients cannot insert raw HealthKit samples'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_step_source_days', 'DELETE'),
  false,
  'authenticated clients cannot delete HealthKit source statistics'
);

select * from finish();
rollback;
