create function pg_temp.make_migration_test_user(uid uuid, email_address text)
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
    email_address,
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
    jsonb_build_object('sub', uid::text, 'email', email_address),
    'email',
    uid::text,
    now(),
    now(),
    now()
  );
end;
$$;

select pg_temp.make_migration_test_user(
  '44444444-4444-4444-8444-444444444444',
  'legacy-deleted@example.com'
);
select pg_temp.make_migration_test_user(
  '55555555-5555-4555-8555-555555555555',
  'active-account@example.com'
);

update public.profiles
set handle = 'legacy_dead',
    display_name = 'Deleted User',
    deleted_at = now()
where user_id = '44444444-4444-4444-8444-444444444444';

update public.profiles
set handle = 'active_keep',
    display_name = 'Active Account'
where user_id = '55555555-5555-4555-8555-555555555555';

insert into public.data_sources (
  id,
  user_id,
  provider,
  source_label,
  connection_route,
  capabilities,
  status,
  revoked_at
) values
  (
    '77777777-7777-4777-8777-777777777777',
    '44444444-4444-4444-8444-444444444444',
    'apple_health',
    'Deleted source',
    'healthkit',
    array['steps']::text[],
    'disconnected',
    now()
  ),
  (
    '88888888-8888-4888-8888-888888888888',
    '55555555-5555-4555-8555-555555555555',
    'apple_health',
    'Apple Health',
    'healthkit',
    array['steps']::text[],
    'healthy',
    null
  );

insert into public.fights (
  id,
  owner_id,
  name,
  state,
  starts_at,
  ends_at,
  time_zone,
  outcome_rule,
  goal_policy,
  stake_kind,
  action_text
) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '44444444-4444-4444-8444-444444444444',
    'Legacy-owned Fight',
    'live',
    now() - interval '1 hour',
    now() + interval '3 days',
    'UTC',
    'highest_total',
    'shared',
    'action',
    'Make coffee'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '55555555-5555-4555-8555-555555555555',
    'Active-owned Fight',
    'live',
    now() - interval '1 hour',
    now() + interval '3 days',
    'UTC',
    'highest_total',
    'shared',
    'action',
    'Make tea'
  );

insert into public.fight_members (
  fight_id,
  user_id,
  state,
  accepted_at,
  selected_source_id,
  current_value
) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '44444444-4444-4444-8444-444444444444',
    'accepted',
    now(),
    '77777777-7777-4777-8777-777777777777',
    1000
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '55555555-5555-4555-8555-555555555555',
    'accepted',
    now(),
    '88888888-8888-4888-8888-888888888888',
    2000
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '44444444-4444-4444-8444-444444444444',
    'accepted',
    now(),
    '77777777-7777-4777-8777-777777777777',
    1000
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '55555555-5555-4555-8555-555555555555',
    'accepted',
    now(),
    '88888888-8888-4888-8888-888888888888',
    2000
  );

insert into public.fight_invites (
  fight_id,
  invited_user_id,
  token_hash,
  expires_at
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '44444444-4444-4444-8444-444444444444',
  'legacy-deleted-account-invite',
  now() + interval '3 days'
);

insert into public.friendships (requester_id, addressee_id, state)
values (
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  'accepted'
);

insert into public.step_days (user_id, day, steps) values
  ('44444444-4444-4444-8444-444444444444', current_date, 1000),
  ('55555555-5555-4555-8555-555555555555', current_date, 2000);

insert into private.healthkit_step_samples (
  user_id,
  sample_id,
  value,
  starts_at,
  ends_at,
  local_day,
  time_zone,
  source_name,
  source_bundle_identifier
) values (
  '44444444-4444-4444-8444-444444444444',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  1000,
  now() - interval '1 hour',
  now(),
  current_date,
  'UTC',
  'iPhone',
  'com.apple.health'
);

insert into private.healthkit_step_sample_deletions (user_id, sample_id)
values (
  '44444444-4444-4444-8444-444444444444',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
);

insert into private.healthkit_step_source_days (
  user_id,
  day,
  starts_at,
  ends_at,
  time_zone,
  source_name,
  source_bundle_identifier,
  steps
) values (
  '44444444-4444-4444-8444-444444444444',
  current_date,
  current_date::timestamptz,
  current_date::timestamptz + interval '1 day',
  'UTC',
  'iPhone',
  'com.apple.health',
  1000
);

insert into private.healthkit_step_syncs (
  user_id,
  time_zone,
  complete_through,
  raw_sample_count,
  deletion_count,
  merged_day_count,
  source_day_count
) values (
  '44444444-4444-4444-8444-444444444444',
  'UTC',
  now(),
  1,
  1,
  1,
  1
);

insert into private.provider_uploads (
  upload_id,
  user_id,
  source_id,
  provider,
  connection_route,
  metric,
  format_version,
  expected_byte_size,
  expected_sha256,
  object_path
) values (
  '99999999-9999-4999-8999-999999999999',
  '44444444-4444-4444-8444-444444444444',
  '77777777-7777-4777-8777-777777777777',
  'apple_health',
  'healthkit',
  'steps',
  1,
  12,
  repeat('a', 64),
  '44444444-4444-4444-8444-444444444444/99999999-9999-4999-8999-999999999999/archive.ndjson'
);

insert into private.provider_events (
  upload_id,
  user_id,
  source_id,
  event_kind,
  external_record_id,
  payload_hash,
  payload,
  occurred_at
) values (
  '99999999-9999-4999-8999-999999999999',
  '44444444-4444-4444-8444-444444444444',
  '77777777-7777-4777-8777-777777777777',
  'add',
  'legacy-event',
  repeat('b', 64),
  '{"steps":1000}'::jsonb,
  now()
);

insert into private.metric_observations (
  user_id,
  source_id,
  external_record_id,
  starts_at,
  ends_at,
  value,
  upload_id,
  scope,
  civil_day,
  input_hash
) values (
  '44444444-4444-4444-8444-444444444444',
  '77777777-7777-4777-8777-777777777777',
  'legacy-observation',
  now() - interval '1 hour',
  now(),
  1000,
  '99999999-9999-4999-8999-999999999999',
  'civil_day',
  current_date,
  repeat('c', 64)
);

insert into public.metric_days (
  user_id,
  source_id,
  metric,
  day,
  value,
  unit,
  input_hash,
  normalization_version,
  calculation_version
) values (
  '44444444-4444-4444-8444-444444444444',
  '77777777-7777-4777-8777-777777777777',
  'steps',
  current_date,
  1000,
  'steps',
  repeat('d', 64),
  1,
  1
);

insert into private.fight_score_snapshots (
  fight_id,
  user_id,
  source_id,
  upload_id,
  cutoff_at,
  value,
  input_hash,
  calculation_version
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '44444444-4444-4444-8444-444444444444',
  '77777777-7777-4777-8777-777777777777',
  '99999999-9999-4999-8999-999999999999',
  now(),
  1000,
  repeat('e', 64),
  1
);

insert into private.apple_sign_in_tokens (
  user_id,
  apple_subject,
  encrypted_refresh_token,
  encryption_iv,
  encryption_tag
) values (
  '44444444-4444-4444-8444-444444444444',
  'legacy-apple-subject',
  'encrypted-token',
  'test-iv',
  'test-tag'
);
