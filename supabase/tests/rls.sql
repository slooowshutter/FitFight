begin;
select plan(6);

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

select pg_temp.make_user('11111111-1111-4111-8111-111111111111', 'maya@example.com');
select pg_temp.make_user('22222222-2222-4222-8222-222222222222', 'leo@example.com');
select pg_temp.make_user('33333333-3333-4333-8333-333333333333', 'ivy@example.com');

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
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'accepted'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'accepted'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333', 'invited');

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

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ select * from public.fight_members $$,
  'accepted member can read fight_members without recursion'
);

select is(
  (select count(*)::integer from public.fight_members),
  3,
  'accepted member sees the whole lineup'
);

select throws_ok(
  $$ insert into public.friendships (requester_id, addressee_id, state)
     values (
       '11111111-1111-4111-8111-111111111111',
       '22222222-2222-4222-8222-222222222222',
       'accepted'
     ) $$,
  '42501',
  'cannot insert an already-accepted friendship'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.fight_members),
  1,
  'invitee sees only their own membership'
);

select is(
  (select count(*)::integer from public.fights),
  1,
  'invitee can still see the fight'
);

reset role;
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ insert into public.friendships (requester_id, addressee_id, state)
     values (
       '11111111-1111-4111-8111-111111111111',
       '22222222-2222-4222-8222-222222222222',
       'pending'
     ) $$,
  'requester can insert a pending friendship'
);

select * from finish();
rollback;
