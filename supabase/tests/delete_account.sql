begin;
select plan(10);

create function pg_temp.make_user(uid uuid, email text)
returns void
language plpgsql
as $$
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    uid,
    'authenticated',
    'authenticated',
    email,
    extensions.crypt('password123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    uid,
    uid,
    jsonb_build_object('sub', uid::text, 'email', email),
    'email',
    uid::text,
    now(),
    now(),
    now()
  );
end;
$$;

create function pg_temp.as_user(uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

select pg_temp.make_user('11111111-1111-4111-8111-111111111111', 'maya@example.com');
select pg_temp.make_user('22222222-2222-4222-8222-222222222222', 'leo@example.com');
select pg_temp.make_user('44444444-4444-4444-8444-444444444444', 'sam@example.com');

insert into public.fights (
  id, owner_id, name, state, starts_at, ends_at, time_zone,
  outcome_rule, goal_policy
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111',
  'Steps',
  'live',
  now(),
  now() + interval '7 days',
  'America/New_York',
  'highest_total',
  'shared'
);

insert into public.fight_members (fight_id, user_id, state) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'accepted');

insert into private.healthkit_step_samples (
  user_id, sample_id, value, starts_at, ends_at, local_day, time_zone,
  source_name, source_bundle_identifier
) values (
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  100, now() - interval '5 minutes', now(), current_date, 'UTC',
  'Apple Watch', 'com.apple.health'
);
insert into private.healthkit_step_sample_deletions (user_id, sample_id) values (
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);
insert into private.healthkit_step_source_days (
  user_id, day, starts_at, ends_at, time_zone,
  source_name, source_bundle_identifier, steps
) values (
  '11111111-1111-4111-8111-111111111111', current_date,
  current_date::timestamptz, (current_date + 1)::timestamptz, 'UTC',
  'Apple Watch', 'com.apple.health', 100
);
insert into private.healthkit_step_syncs (
  user_id, time_zone, accessible_from, complete_through
) values (
  '11111111-1111-4111-8111-111111111111', 'UTC', now() - interval '5 minutes', now()
);

select is(
  has_function_privilege('anon', 'public.delete_own_account()', 'EXECUTE'),
  false,
  'anon cannot delete an account'
);

select pg_temp.as_user('44444444-4444-4444-8444-444444444444');
set local role authenticated;

select lives_ok(
  $$ select public.delete_own_account() $$,
  'a user with no fights can delete their account'
);

reset role;

select is(
  (select count(*)::integer from public.profiles
    where user_id = '44444444-4444-4444-8444-444444444444'),
  0,
  'account deletion removes the unused profile'
);

select is(
  (select count(*)::integer from auth.users
    where id = '44444444-4444-4444-8444-444444444444'),
  0,
  'account deletion removes the unused auth user'
);

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ select public.delete_own_account() $$,
  'a fight owner can still delete their login'
);

reset role;

select is(
  (select deleted_at is not null from public.profiles
    where user_id = '11111111-1111-4111-8111-111111111111'),
  true,
  'fight history keeps an anonymized profile'
);
select is(
  (select count(*)::integer from private.healthkit_step_samples
    where user_id = '11111111-1111-4111-8111-111111111111'),
  0,
  'account deletion removes raw HealthKit samples'
);
select is(
  (select count(*)::integer from private.healthkit_step_sample_deletions
    where user_id = '11111111-1111-4111-8111-111111111111'),
  0,
  'account deletion removes HealthKit deletion tombstones'
);
select is(
  (select count(*)::integer from private.healthkit_step_source_days
    where user_id = '11111111-1111-4111-8111-111111111111'),
  0,
  'account deletion removes HealthKit source statistics'
);
select is(
  (select count(*)::integer from private.healthkit_step_syncs
    where user_id = '11111111-1111-4111-8111-111111111111'),
  0,
  'account deletion removes HealthKit sync state'
);

select * from finish();
rollback;
