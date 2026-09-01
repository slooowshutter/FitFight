begin;
select plan(15);

select is(
  (select count(*) from auth.users
    where id = '44444444-4444-4444-8444-444444444444'),
  0::bigint,
  'legacy Auth user is permanently deleted'
);

select is(
  (select count(*) from public.profiles
    where user_id = '44444444-4444-4444-8444-444444444444'),
  0::bigint,
  'legacy profile is permanently deleted'
);

select is(
  (select count(*) from auth.users
    where id = '55555555-5555-4555-8555-555555555555'),
  1::bigint,
  'active Auth user is preserved'
);

select is(
  (select count(*) from auth.identities
    where user_id = '55555555-5555-4555-8555-555555555555'),
  1::bigint,
  'active sign-in identity is preserved'
);

select is(
  (select handle from public.profiles
    where user_id = '55555555-5555-4555-8555-555555555555'
      and deleted_at is null),
  'active_keep',
  'active profile is preserved unchanged'
);

select is(
  (select count(*) from public.fights
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0::bigint,
  'Fight owned by the legacy account is deleted'
);

select is(
  (select count(*) from public.fights
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1::bigint,
  'Fight owned by the active account is preserved'
);

select is(
  (select count(*) from public.fight_members
    where fight_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and user_id = '55555555-5555-4555-8555-555555555555'),
  1::bigint,
  'active membership in the surviving Fight is preserved'
);

select is(
  (
    select sum(row_count)
    from (
      select count(*) as row_count
      from public.fight_members
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*)
      from public.fight_invites
      where invited_user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*)
      from public.friendships
      where requester_id = '44444444-4444-4444-8444-444444444444'
         or addressee_id = '44444444-4444-4444-8444-444444444444'
    ) as counts
  ),
  0::numeric,
  'legacy Fight relationships are deleted'
);

select is(
  (
    select sum(row_count)
    from (
      select count(*) as row_count from public.data_sources
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from public.step_days
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from public.metric_days
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.healthkit_step_samples
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.healthkit_step_sample_deletions
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.healthkit_step_source_days
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.healthkit_step_syncs
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.provider_uploads
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.provider_events
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.metric_observations
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.fight_score_snapshots
      where user_id = '44444444-4444-4444-8444-444444444444'
      union all
      select count(*) from private.apple_sign_in_tokens
      where user_id = '44444444-4444-4444-8444-444444444444'
    ) as counts
  ),
  0::numeric,
  'all remaining legacy account data is deleted'
);

select is(
  (select count(*) from public.data_sources
    where id = '88888888-8888-4888-8888-888888888888'
      and user_id = '55555555-5555-4555-8555-555555555555'),
  1::bigint,
  'active data source is preserved'
);

select is(
  (select steps from public.step_days
    where user_id = '55555555-5555-4555-8555-555555555555'
      and day = current_date),
  2000,
  'active Steps are preserved'
);

select lives_ok(
  $$
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
      '66666666-6666-4666-8666-666666666666',
      'authenticated',
      'authenticated',
      'replacement-account@example.com',
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
    )
  $$,
  'a replacement account can be created'
);

select lives_ok(
  $$
    update public.profiles
    set handle = 'legacy_dead'
    where user_id = '66666666-6666-4666-8666-666666666666'
  $$,
  'the replacement account can claim the legacy username'
);

select is(
  (select handle from public.profiles
    where user_id = '66666666-6666-4666-8666-666666666666'),
  'legacy_dead',
  'the legacy username belongs to the replacement account'
);

select * from finish();
rollback;
