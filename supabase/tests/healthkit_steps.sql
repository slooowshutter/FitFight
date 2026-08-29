begin;
select plan(15);

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

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) values (
    uid, uid, jsonb_build_object('sub', uid::text, 'email', email),
    'email', uid::text, now(), now(), now()
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

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ select public.ingest_healthkit_steps(
    jsonb_build_object(
      'samples', jsonb_build_array(jsonb_build_object(
        'sample_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'value', 1200,
        'unit', 'count',
        'starts_at', now() - interval '1 hour',
        'ends_at', now(),
        'local_day', current_date,
        'time_zone', 'UTC',
        'source_name', 'Apple Watch',
        'source_bundle_identifier', 'com.apple.health',
        'source_os_version', '26.0.0',
        'metadata', jsonb_build_object('HKWasUserEntered', jsonb_build_object(
          'kind', 'boolean', 'value', 'false', 'objc_type', 'c'
        )),
        'user_entered', false
      )),
      'merged_days', jsonb_build_array(jsonb_build_object(
        'day', current_date,
        'steps', 1200
      )),
      'source_days', jsonb_build_array(jsonb_build_object(
        'day', current_date,
        'starts_at', current_date::timestamptz,
        'ends_at', (current_date + 1)::timestamptz,
        'time_zone', 'UTC',
        'source_name', 'Apple Watch',
        'source_bundle_identifier', 'com.apple.health',
        'steps', 1200
      )),
      'sync', jsonb_build_object(
        'time_zone', 'UTC',
        'accessible_from', now() - interval '1 hour',
        'complete_through', now()
      )
    )
  ) $$,
  'signed-in user can archive a complete HealthKit batch'
);

select is(
  (select count(*)::integer from private.healthkit_step_samples),
  1,
  'owner can see the archived raw sample'
);
select is(
  (select steps from public.step_days where day = current_date),
  1200,
  'Apple-merged daily total is the canonical score'
);
select is(
  (select count(*)::integer from private.healthkit_step_source_days),
  1,
  'source-separated daily statistic is archived'
);
select is(
  (select count(*)::integer from private.healthkit_step_syncs),
  1,
  'sync provenance is archived'
);

select lives_ok(
  $$ select public.ingest_healthkit_steps(
    jsonb_build_object(
      'deletions', jsonb_build_array(jsonb_build_object(
        'sample_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      )),
      'merged_days', jsonb_build_array(jsonb_build_object(
        'day', current_date,
        'steps', 0
      ))
    )
  ) $$,
  'HealthKit deletion can retract derived statistics'
);
select is(
  (select count(*)::integer from private.healthkit_step_sample_deletions),
  1,
  'HealthKit deletion UUID is retained as a tombstone'
);
select is(
  (select count(*)::integer from private.healthkit_step_samples),
  1,
  'deleted raw record remains available for audit'
);
select is(
  (select count(*)::integer from private.healthkit_step_source_days),
  0,
  'recalculated day clears obsolete source statistics'
);
select is(
  (select steps from public.step_days where day = current_date),
  0,
  'recalculated Apple total replaces the previous score'
);

reset role;

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
insert into public.step_days (user_id, day, steps) values
  ('11111111-1111-4111-8111-111111111111', date '2000-01-01', 999);

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select is(
  (select count(*)::integer from private.healthkit_step_samples),
  0,
  'another user cannot read raw HealthKit samples'
);
select is(
  (select count(*)::integer from private.healthkit_step_source_days),
  0,
  'another user cannot read source statistics'
);
select is(
  (select count(*)::integer from private.healthkit_step_syncs),
  0,
  'another user cannot read sync provenance'
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
  'new row violates row-level security policy for table "healthkit_step_samples"',
  'another user cannot forge raw samples for the owner'
);
select is(
  (select count(*)::integer from public.step_days),
  1,
  'fight peer sees merged totals only inside the shared Fight window'
);

select * from finish();
rollback;
