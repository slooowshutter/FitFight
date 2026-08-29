begin;
select plan(7);

create function pg_temp.make_user(uid uuid, email text)
returns void
language plpgsql
as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated',
    'authenticated', email, extensions.crypt('password123', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), '', '', '', ''
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
select pg_temp.make_user('33333333-3333-4333-8333-333333333333', 'ivy@example.com');

insert into private.healthkit_step_samples (
  user_id, sample_id, value, starts_at, ends_at, local_day, time_zone,
  source_name, source_bundle_identifier
) values (
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  1200, now() - interval '1 hour', now(), current_date, 'UTC',
  'Apple Watch', 'com.apple.health'
);
insert into private.healthkit_step_source_days (
  user_id, day, starts_at, ends_at, time_zone,
  source_name, source_bundle_identifier, steps
) values (
  '11111111-1111-4111-8111-111111111111', current_date,
  current_date::timestamptz, (current_date + 1)::timestamptz, 'UTC',
  'Apple Watch', 'com.apple.health', 1200
);
insert into public.step_days (user_id, day, steps) values
  ('11111111-1111-4111-8111-111111111111', current_date, 1200),
  ('11111111-1111-4111-8111-111111111111', date '2000-01-01', 999);

insert into public.fights (
  id, owner_id, name, state, starts_at, ends_at, time_zone,
  outcome_rule, goal_policy
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  'Steps', 'live', now() - interval '1 day', now() + interval '1 day',
  'UTC', 'highest_total', 'shared'
);
insert into public.fight_members (fight_id, user_id, state) values
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '11111111-1111-4111-8111-111111111111', 'accepted'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'accepted');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select is(
  (select count(*)::integer from public.step_days),
  2,
  'the owner sees all of their merged daily totals'
);
select throws_ok(
  $$ select count(*) from private.healthkit_step_samples $$,
  '42501',
  'permission denied for table healthkit_step_samples',
  'the app cannot query the private raw archive'
);
select throws_ok(
  $$ insert into private.healthkit_step_samples (
       user_id, sample_id, value, starts_at, ends_at, local_day, time_zone,
       source_name, source_bundle_identifier
     ) values (
       '11111111-1111-4111-8111-111111111111',
       'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
       10, now(), now(), current_date, 'UTC', 'Fake', 'example.fake'
     ) $$,
  '42501',
  'permission denied for table healthkit_step_samples',
  'the app cannot write the private raw archive'
);

reset role;
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select is(
  (select count(*)::integer from public.step_days),
  1,
  'a Fight peer sees merged totals only inside the shared Fight window'
);
select is(
  (select steps from public.step_days where day = current_date),
  1200,
  'a Fight peer sees the Apple-merged score'
);
select throws_ok(
  $$ select count(*) from private.healthkit_step_source_days $$,
  '42501',
  'permission denied for table healthkit_step_source_days',
  'a Fight peer cannot query source statistics'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.step_days),
  0,
  'an unrelated user sees no merged totals'
);

select * from finish();
rollback;
