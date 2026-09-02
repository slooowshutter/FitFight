begin;
select plan(20);

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

select lives_ok(
  $$ insert into public.friendships (requester_id, addressee_id, state)
     values (
       '11111111-1111-4111-8111-111111111111',
       '22222222-2222-4222-8222-222222222222',
       'accepted'
     ) $$,
  'requester can add a friend without a pending request'
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
       '33333333-3333-4333-8333-333333333333',
       'pending'
     ) $$,
  'requester can still insert a pending friendship'
);

select lives_ok(
  $$ insert into public.fights (
       id, owner_id, name, state, starts_at, ends_at, time_zone,
       outcome_rule, goal_policy
     ) values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '11111111-1111-4111-8111-111111111111',
       'Phone fight',
       'live',
       now(),
       now() + interval '3 days',
       'America/New_York',
       'highest_total',
       'shared'
     ) $$,
  'owner can insert a steps fight'
);

select lives_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '11111111-1111-4111-8111-111111111111',
       'accepted'
     ) $$,
  'owner can join their fight'
);

select lives_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '22222222-2222-4222-8222-222222222222',
       'invited'
     ) $$,
  'owner can invite a friend'
);

select throws_ok(
  $$ insert into public.step_days (user_id, day, steps)
     values (
       '11111111-1111-4111-8111-111111111111',
       current_date,
       8000
     ) $$,
  '42501',
  'permission denied for table step_days',
  'clients cannot write server-owned step totals'
);

reset role;
insert into public.step_days (user_id, day, steps)
values (
  '11111111-1111-4111-8111-111111111111',
  current_date,
  8000
);
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select throws_ok(
  $$ insert into public.fights (
       id, owner_id, name, state, starts_at, ends_at, time_zone,
       outcome_rule, goal_policy
     ) values (
       'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
       '11111111-1111-4111-8111-111111111111',
       'Stolen',
       'live',
       now(),
       now() + interval '3 days',
       'America/New_York',
       'highest_total',
       'shared'
     ) $$,
  '42501',
  'new row violates row-level security policy for table "fights"',
  'cannot create a fight as someone else'
);

select is(
  (select steps from public.step_days
    where user_id = '11111111-1111-4111-8111-111111111111'
      and day = current_date),
  8000,
  'accepted fight peer can read the other person steps'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.step_days),
  0,
  'invitee who has not accepted cannot read peer steps'
);

select lives_ok(
  $$ update public.fight_members
        set state = 'accepted',
            accepted_at = now()
      where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        and user_id = '33333333-3333-4333-8333-333333333333' $$,
  'invitee can accept their own membership'
);

reset role;
insert into public.feedback_posts (id, author_id, kind, title, body)
values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111',
  'bug',
  'Steps chart is blank',
  'The daily Steps chart on a live fight stays empty after a successful sync.'
);

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select is(
  (select count(*)::integer from public.feedback_posts),
  1,
  'signed-in users can read the public request board'
);

select throws_ok(
  $$ insert into public.feedback_posts (author_id, kind, title, body)
     values (
       '22222222-2222-4222-8222-222222222222',
       'feature',
       'Show weekly totals',
       'A weekly Steps total on You would make it easier to plan a fight.'
     ) $$,
  '42501',
  'permission denied for table feedback_posts',
  'clients cannot insert feedback posts'
);

select throws_ok(
  $$ insert into public.feedback_comments (post_id, author_id, body)
     values (
       'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
       '22222222-2222-4222-8222-222222222222',
       'I see this too'
     ) $$,
  '42501',
  'permission denied for table feedback_comments',
  'clients cannot insert feedback comments'
);

select throws_ok(
  $$ insert into public.feedback_votes (post_id, user_id)
     values (
       'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
       '22222222-2222-4222-8222-222222222222'
     ) $$,
  '42501',
  'permission denied for table feedback_votes',
  'clients cannot insert feedback votes'
);

reset role;
select pg_temp.as_user('44444444-4444-4444-8444-444444444444');
set local role authenticated;

select throws_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       '44444444-4444-4444-8444-444444444444',
       'accepted'
     ) $$,
  '42501',
  'new row violates row-level security policy for table "fight_members"',
  'strangers cannot client-insert themselves onto a fight'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.fight_series),
  0,
  'unrelated users cannot read a series they are not in'
);

select throws_ok(
  $$ update public.fight_members
        set current_value = 999999
      where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        and user_id = '33333333-3333-4333-8333-333333333333' $$,
  '42501',
  'permission denied for table fight_members',
  'clients cannot overwrite their own score'
);

reset role;
update public.fights
set state = 'final'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select isnt(
  (select finalized_at from public.fight_members
    where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and user_id = '11111111-1111-4111-8111-111111111111'),
  null,
  'moving a fight to final freezes accepted member scores'
);

update public.fight_members
set current_value = 1
where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and user_id = '11111111-1111-4111-8111-111111111111';

select ok(
  (select current_value is null from public.fight_members
    where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and user_id = '11111111-1111-4111-8111-111111111111'),
  'finalized member scores ignore later aggregation writes'
);

update public.fights
set state = 'live'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select state::text from public.fights
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'final',
  'a final fight cannot return to live'
);

select * from finish();
rollback;
