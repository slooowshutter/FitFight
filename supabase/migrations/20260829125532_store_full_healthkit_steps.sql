-- Preserve every accessible HealthKit Steps representation while keeping the
-- Apple-merged daily total as the only client-visible scoring input.

create table private.healthkit_step_samples (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  sample_id uuid not null,
  value numeric not null,
  unit text not null default 'count',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  local_day date not null,
  time_zone text not null,
  source_name text not null,
  source_bundle_identifier text not null,
  source_version text,
  source_product_type text,
  source_os_version text,
  device_name text,
  device_manufacturer text,
  device_model text,
  device_hardware_version text,
  device_firmware_version text,
  device_software_version text,
  device_local_identifier text,
  device_udi_identifier text,
  metadata jsonb not null default '{}',
  user_entered boolean,
  first_received_at timestamptz not null default now(),
  last_received_at timestamptz not null default now(),
  primary key (user_id, sample_id),
  constraint healthkit_step_samples_value_nonnegative check (value >= 0),
  constraint healthkit_step_samples_window check (ends_at >= starts_at),
  constraint healthkit_step_samples_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint healthkit_step_samples_source_nonempty check (source_bundle_identifier <> '')
);

create index healthkit_step_samples_user_time_idx
  on private.healthkit_step_samples (user_id, starts_at, ends_at);
create index healthkit_step_samples_user_source_idx
  on private.healthkit_step_samples (user_id, source_bundle_identifier, starts_at);

-- HealthKit deletions contain an object UUID but not the deleted sample body.
-- Keep the original sample and a tombstone so edits/deletes remain auditable.
create table private.healthkit_step_sample_deletions (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  sample_id uuid not null,
  first_received_at timestamptz not null default now(),
  last_received_at timestamptz not null default now(),
  primary key (user_id, sample_id)
);

create table private.healthkit_step_source_days (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  day date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_zone text not null,
  source_name text not null,
  source_bundle_identifier text not null,
  steps numeric not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, source_bundle_identifier),
  constraint healthkit_step_source_days_steps_nonnegative check (steps >= 0),
  constraint healthkit_step_source_days_window check (ends_at > starts_at),
  constraint healthkit_step_source_days_source_nonempty check (source_bundle_identifier <> '')
);

create index healthkit_step_source_days_user_time_idx
  on private.healthkit_step_source_days (user_id, day);

create table private.healthkit_step_syncs (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  time_zone text not null,
  accessible_from timestamptz,
  complete_through timestamptz not null,
  raw_sample_count bigint not null default 0,
  deletion_count bigint not null default 0,
  merged_day_count bigint not null default 0,
  source_day_count bigint not null default 0,
  last_success_at timestamptz not null default now(),
  constraint healthkit_step_syncs_counts_nonnegative check (
    raw_sample_count >= 0
    and deletion_count >= 0
    and merged_day_count >= 0
    and source_day_count >= 0
  )
);

revoke all on table private.healthkit_step_samples from public, anon;
revoke all on table private.healthkit_step_sample_deletions from public, anon;
revoke all on table private.healthkit_step_source_days from public, anon;
revoke all on table private.healthkit_step_syncs from public, anon;

grant select, insert, update
  on private.healthkit_step_samples,
     private.healthkit_step_sample_deletions,
     private.healthkit_step_syncs
  to authenticated;
grant select, insert, update, delete
  on private.healthkit_step_source_days
  to authenticated;
grant all
  on private.healthkit_step_samples,
     private.healthkit_step_sample_deletions,
     private.healthkit_step_source_days,
     private.healthkit_step_syncs
  to postgres, service_role;

alter table private.healthkit_step_samples enable row level security;
alter table private.healthkit_step_sample_deletions enable row level security;
alter table private.healthkit_step_source_days enable row level security;
alter table private.healthkit_step_syncs enable row level security;

alter table private.healthkit_step_samples force row level security;
alter table private.healthkit_step_sample_deletions force row level security;
alter table private.healthkit_step_source_days force row level security;
alter table private.healthkit_step_syncs force row level security;

create policy healthkit_step_samples_select_own
  on private.healthkit_step_samples
  for select
  to authenticated
  using (user_id = (select auth.uid()));
create policy healthkit_step_samples_insert_own
  on private.healthkit_step_samples
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));
create policy healthkit_step_samples_update_own
  on private.healthkit_step_samples
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy healthkit_step_sample_deletions_select_own
  on private.healthkit_step_sample_deletions
  for select
  to authenticated
  using (user_id = (select auth.uid()));
create policy healthkit_step_sample_deletions_insert_own
  on private.healthkit_step_sample_deletions
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));
create policy healthkit_step_sample_deletions_update_own
  on private.healthkit_step_sample_deletions
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy healthkit_step_source_days_select_own
  on private.healthkit_step_source_days
  for select
  to authenticated
  using (user_id = (select auth.uid()));
create policy healthkit_step_source_days_insert_own
  on private.healthkit_step_source_days
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));
create policy healthkit_step_source_days_update_own
  on private.healthkit_step_source_days
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy healthkit_step_source_days_delete_own
  on private.healthkit_step_source_days
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

create policy healthkit_step_syncs_select_own
  on private.healthkit_step_syncs
  for select
  to authenticated
  using (user_id = (select auth.uid()));
create policy healthkit_step_syncs_insert_own
  on private.healthkit_step_syncs
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));
create policy healthkit_step_syncs_update_own
  on private.healthkit_step_syncs
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- This is SECURITY INVOKER. The caller's grants and RLS remain in force, and
-- the function derives the owner from auth.uid() instead of accepting a user ID.
create function public.ingest_healthkit_steps(_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
declare
  uid uuid := auth.uid();
  samples jsonb := coalesce(_payload->'samples', '[]'::jsonb);
  deletions jsonb := coalesce(_payload->'deletions', '[]'::jsonb);
  merged_days jsonb := coalesce(_payload->'merged_days', '[]'::jsonb);
  source_days jsonb := coalesce(_payload->'source_days', '[]'::jsonb);
  sync_state jsonb := _payload->'sync';
  samples_written integer := 0;
  deletions_written integer := 0;
  merged_days_written integer := 0;
  source_days_written integer := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if jsonb_typeof(_payload) <> 'object'
     or jsonb_typeof(samples) <> 'array'
     or jsonb_typeof(deletions) <> 'array'
     or jsonb_typeof(merged_days) <> 'array'
     or jsonb_typeof(source_days) <> 'array' then
    raise exception 'Invalid HealthKit payload';
  end if;

  if jsonb_array_length(samples) > 250
     or jsonb_array_length(deletions) > 500
     or jsonb_array_length(merged_days) > 45
     or jsonb_array_length(source_days) > 1000 then
    raise exception 'HealthKit payload exceeds batch limit';
  end if;

  insert into private.healthkit_step_samples (
    user_id, sample_id, value, unit, starts_at, ends_at, local_day, time_zone,
    source_name, source_bundle_identifier, source_version, source_product_type,
    source_os_version, device_name, device_manufacturer, device_model,
    device_hardware_version, device_firmware_version, device_software_version,
    device_local_identifier, device_udi_identifier, metadata, user_entered
  )
  select
    uid, sample.sample_id, sample.value, coalesce(sample.unit, 'count'),
    sample.starts_at, sample.ends_at, sample.local_day, sample.time_zone,
    sample.source_name, sample.source_bundle_identifier, sample.source_version,
    sample.source_product_type, sample.source_os_version, sample.device_name,
    sample.device_manufacturer, sample.device_model, sample.device_hardware_version,
    sample.device_firmware_version, sample.device_software_version,
    sample.device_local_identifier, sample.device_udi_identifier,
    coalesce(sample.metadata, '{}'::jsonb), sample.user_entered
  from jsonb_to_recordset(samples) as sample (
    sample_id uuid,
    value numeric,
    unit text,
    starts_at timestamptz,
    ends_at timestamptz,
    local_day date,
    time_zone text,
    source_name text,
    source_bundle_identifier text,
    source_version text,
    source_product_type text,
    source_os_version text,
    device_name text,
    device_manufacturer text,
    device_model text,
    device_hardware_version text,
    device_firmware_version text,
    device_software_version text,
    device_local_identifier text,
    device_udi_identifier text,
    metadata jsonb,
    user_entered boolean
  )
  on conflict (user_id, sample_id) do update
    set value = excluded.value,
        unit = excluded.unit,
        starts_at = excluded.starts_at,
        ends_at = excluded.ends_at,
        local_day = excluded.local_day,
        time_zone = excluded.time_zone,
        source_name = excluded.source_name,
        source_bundle_identifier = excluded.source_bundle_identifier,
        source_version = excluded.source_version,
        source_product_type = excluded.source_product_type,
        source_os_version = excluded.source_os_version,
        device_name = excluded.device_name,
        device_manufacturer = excluded.device_manufacturer,
        device_model = excluded.device_model,
        device_hardware_version = excluded.device_hardware_version,
        device_firmware_version = excluded.device_firmware_version,
        device_software_version = excluded.device_software_version,
        device_local_identifier = excluded.device_local_identifier,
        device_udi_identifier = excluded.device_udi_identifier,
        metadata = excluded.metadata,
        user_entered = excluded.user_entered,
        last_received_at = now();
  get diagnostics samples_written = row_count;

  insert into private.healthkit_step_sample_deletions (user_id, sample_id)
  select uid, deletion.sample_id
  from jsonb_to_recordset(deletions) as deletion (sample_id uuid)
  on conflict (user_id, sample_id) do update
    set last_received_at = now();
  get diagnostics deletions_written = row_count;

  if jsonb_array_length(merged_days) > 0 then
    delete from private.healthkit_step_source_days as stored
    using jsonb_to_recordset(merged_days) as merged (day date, steps integer)
    where stored.user_id = uid
      and stored.day = merged.day;

    insert into public.step_days (user_id, day, steps, updated_at)
    select uid, merged.day, merged.steps, now()
    from jsonb_to_recordset(merged_days) as merged (day date, steps integer)
    on conflict (user_id, day) do update
      set steps = excluded.steps,
          updated_at = now();
    get diagnostics merged_days_written = row_count;
  end if;

  insert into private.healthkit_step_source_days (
    user_id, day, starts_at, ends_at, time_zone,
    source_name, source_bundle_identifier, steps, updated_at
  )
  select
    uid, source_day.day, source_day.starts_at, source_day.ends_at,
    source_day.time_zone, source_day.source_name,
    source_day.source_bundle_identifier, source_day.steps, now()
  from jsonb_to_recordset(source_days) as source_day (
    day date,
    starts_at timestamptz,
    ends_at timestamptz,
    time_zone text,
    source_name text,
    source_bundle_identifier text,
    steps numeric
  )
  on conflict (user_id, day, source_bundle_identifier) do update
    set starts_at = excluded.starts_at,
        ends_at = excluded.ends_at,
        time_zone = excluded.time_zone,
        source_name = excluded.source_name,
        steps = excluded.steps,
        updated_at = now();
  get diagnostics source_days_written = row_count;

  if sync_state is not null and jsonb_typeof(sync_state) = 'object' then
    insert into private.healthkit_step_syncs (
      user_id, time_zone, accessible_from, complete_through,
      raw_sample_count, deletion_count, merged_day_count, source_day_count,
      last_success_at
    ) values (
      uid,
      sync_state->>'time_zone',
      nullif(sync_state->>'accessible_from', '')::timestamptz,
      (sync_state->>'complete_through')::timestamptz,
      (select count(*) from private.healthkit_step_samples where user_id = uid),
      (select count(*) from private.healthkit_step_sample_deletions where user_id = uid),
      (select count(*) from public.step_days where user_id = uid),
      (select count(*) from private.healthkit_step_source_days where user_id = uid),
      now()
    )
    on conflict (user_id) do update
      set time_zone = excluded.time_zone,
          accessible_from = excluded.accessible_from,
          complete_through = excluded.complete_through,
          raw_sample_count = excluded.raw_sample_count,
          deletion_count = excluded.deletion_count,
          merged_day_count = excluded.merged_day_count,
          source_day_count = excluded.source_day_count,
          last_success_at = now();
  end if;

  return jsonb_build_object(
    'samples', samples_written,
    'deletions', deletions_written,
    'mergedDays', merged_days_written,
    'sourceDays', source_days_written
  );
end;
$$;

revoke all on function public.ingest_healthkit_steps(jsonb) from public, anon;
grant execute on function public.ingest_healthkit_steps(jsonb) to authenticated;

-- Only merged daily totals are shared, and only for dates covered by a Fight
-- accepted by both people. Full raw/source history remains self-only.
create function private.current_user_shares_accepted_fight_day(_other uuid, _day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_members as me
    join public.fight_members as them
      on them.fight_id = me.fight_id
    join public.fights as fight
      on fight.id = me.fight_id
    where me.user_id = auth.uid()
      and them.user_id = _other
      and me.state = 'accepted'
      and them.state = 'accepted'
      and _day >= (fight.starts_at at time zone fight.time_zone)::date
      and _day <= ((fight.ends_at - interval '1 microsecond') at time zone fight.time_zone)::date
  );
$$;

revoke all on function private.current_user_shares_accepted_fight_day(uuid, date) from public;
grant execute on function private.current_user_shares_accepted_fight_day(uuid, date) to authenticated;

drop policy step_days_select_self_or_fight on public.step_days;
create policy step_days_select_self_or_fight
  on public.step_days
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.current_user_shares_accepted_fight_day(user_id, day)
  );

-- Raw health records must disappear even when an anonymized profile remains to
-- preserve completed Fight history.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  keep_profile boolean;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from private.healthkit_step_source_days where user_id = uid;
  delete from private.healthkit_step_sample_deletions where user_id = uid;
  delete from private.healthkit_step_samples where user_id = uid;
  delete from private.healthkit_step_syncs where user_id = uid;

  update public.profiles
     set deleted_at = now(),
         display_name = 'Deleted User',
         avatar_path = null,
         time_zone = null
   where user_id = uid;

  delete from auth.sessions where user_id = uid;
  delete from auth.refresh_tokens where user_id = uid::text;
  delete from auth.identities where user_id = uid;

  keep_profile := exists (
    select 1 from public.fights where owner_id = uid
    union all
    select 1 from public.fight_members where user_id = uid
    union all
    select 1 from public.friendships
     where requester_id = uid or addressee_id = uid
  );

  if not keep_profile then
    delete from auth.users where id = uid;
  end if;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
