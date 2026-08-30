begin;
select plan(31);

select has_schema('private', 'private schema exists');
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'friendships', 'friendships exists');
select has_table('public', 'fights', 'fights exists');
select has_table('public', 'fight_members', 'fight_members exists');
select has_table('public', 'fight_invites', 'fight_invites exists');
select has_table('public', 'data_sources', 'data_sources exists');
select has_table('public', 'step_days', 'step_days exists');
select has_table('private', 'metric_observations', 'observations stay private');

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
select is(
  has_table_privilege('anon', 'private.provider_uploads', 'SELECT'),
  false,
  'anon cannot read provider uploads'
);
select is(
  has_table_privilege('authenticated', 'private.provider_uploads', 'SELECT'),
  false,
  'authenticated clients cannot read provider uploads'
);

select * from finish();
rollback;
