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

revoke all
  on private.healthkit_step_samples,
     private.healthkit_step_sample_deletions,
     private.healthkit_step_source_days,
     private.healthkit_step_syncs
  from authenticated;
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
