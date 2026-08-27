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
    '{"full_name":"Sam"}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
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

select pg_temp.make_user('55555555-5555-4555-8555-555555555555', 'sam@example.com');
select pg_temp.make_user('66666666-6666-4666-8666-666666666666', 'ivy@example.com');

select pg_temp.as_user('55555555-5555-4555-8555-555555555555');
set local role authenticated;

select lives_ok(
  $$ select public.ensure_own_profile() $$,
  'ensure is a no-op when the signup trigger already made a profile'
);

reset role;

select is(
  (select display_name from public.profiles
    where user_id = '55555555-5555-4555-8555-555555555555'),
  'Sam',
  'existing profile keeps its display name'
);

delete from public.profiles
 where user_id = '66666666-6666-4666-8666-666666666666';

select pg_temp.as_user('66666666-6666-4666-8666-666666666666');
set local role authenticated;

select lives_ok(
  $$ select public.ensure_own_profile() $$,
  'ensure creates a profile when the trigger missed'
);

reset role;

select ok(
  exists (
    select 1 from public.profiles
     where user_id = '66666666-6666-4666-8666-666666666666'
       and deleted_at is null
  ),
  'missing profile is created'
);

update public.profiles
   set deleted_at = now(),
       display_name = 'Deleted User'
 where user_id = '55555555-5555-4555-8555-555555555555';

select pg_temp.as_user('55555555-5555-4555-8555-555555555555');
set local role authenticated;

select lives_ok(
  $$ select public.ensure_own_profile() $$,
  'ensure undeletes a soft-deleted profile'
);

reset role;

select is(
  (select deleted_at is null from public.profiles
    where user_id = '55555555-5555-4555-8555-555555555555'),
  true,
  'soft-deleted profile is visible again'
);

select * from finish();
rollback;
