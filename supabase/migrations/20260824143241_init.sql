-- FitFight v1 schema. Steps only. Follow docs/system-design.md; do not add
-- Active Minutes, Workout Count, or client-writable scores here.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;
grant usage on schema private to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.fight_state as enum (
  'draft',
  'inviting',
  'scheduled',
  'live',
  'awaiting_final_sync',
  'final',
  'cancelled'
);

create type public.fight_member_state as enum (
  'invited',
  'accepted',
  'declined',
  'withdrawn',
  'disqualified'
);

create type public.goal_policy as enum (
  'shared',
  'personal',
  'recommended_personal'
);

create type public.outcome_rule as enum (
  'highest_total',
  'proportional',
  'hit_your_goal'
);

create type public.friendship_state as enum (
  'pending',
  'accepted',
  'declined'
);

create type public.data_source_status as enum (
  'healthy',
  'syncing',
  'action_required',
  'provider_delayed',
  'disconnected'
);

create type public.stake_kind as enum (
  'bragging',
  'money',
  'action'
);

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique,
  display_name text not null,
  avatar_path text,
  time_zone text,
  deleted_at timestamptz,
  constraint profiles_handle_format check (handle ~ '^[a-z0-9_]{2,30}$')
);

create table public.friendships (
  requester_id uuid not null references public.profiles (user_id) on delete cascade,
  addressee_id uuid not null references public.profiles (user_id) on delete cascade,
  state public.friendship_state not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  constraint friendships_not_self check (requester_id <> addressee_id)
);

create unique index friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table public.fights (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (user_id),
  name text not null,
  state public.fight_state not null default 'draft',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_zone text not null,
  metric text not null default 'steps',
  metric_definition_version integer not null default 1,
  outcome_rule public.outcome_rule not null,
  goal_policy public.goal_policy not null,
  default_goal_value numeric,
  tie_rule text not null default 'split_evenly',
  stake_kind public.stake_kind not null default 'bragging',
  stake_minor integer,
  currency text,
  action_text text,
  rules_version integer not null default 1,
  scoring_engine_version integer not null default 1,
  final_sync_grace_seconds integer not null default 86400,
  created_at timestamptz not null default now(),
  constraint fights_window check (ends_at > starts_at),
  constraint fights_metric_steps_only check (metric = 'steps'),
  constraint fights_stake_minor_nonnegative check (stake_minor is null or stake_minor >= 0)
);

create table public.data_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  provider text not null,
  source_label text not null,
  contributing_source_labels text[] not null default '{}',
  connection_route text not null,
  capabilities text[] not null default '{}',
  status public.data_source_status not null default 'healthy',
  consent_version integer not null default 1,
  connected_at timestamptz not null default now(),
  revoked_at timestamptz,
  last_success_at timestamptz,
  complete_through timestamptz,
  last_error_code text,
  constraint data_sources_user_provider_route unique (user_id, provider, connection_route)
);

create table public.fight_members (
  fight_id uuid not null references public.fights (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id),
  state public.fight_member_state not null default 'invited',
  accepted_at timestamptz,
  selected_source_id uuid references public.data_sources (id),
  source_label text,
  personal_target numeric,
  target_origin text,
  target_formula_version integer,
  acceptance_copy_version integer,
  current_value numeric,
  rank integer,
  outcome_minor integer,
  freshness text,
  input_revision integer,
  final_value numeric,
  finalized_at timestamptz,
  primary key (fight_id, user_id)
);

create table public.fight_invites (
  id uuid primary key default gen_random_uuid(),
  fight_id uuid not null references public.fights (id) on delete cascade,
  invited_user_id uuid references public.profiles (user_id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  accepted_at timestamptz
);

create table private.metric_observations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id),
  external_record_id text not null,
  metric text not null default 'steps',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  value numeric not null,
  unit text not null default 'steps',
  revision integer not null default 1,
  provenance jsonb not null default '{}',
  retracted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint metric_observations_window check (ends_at > starts_at),
  constraint metric_observations_metric_steps_only check (metric = 'steps'),
  constraint metric_observations_value_nonnegative check (value >= 0),
  constraint metric_observations_source_external_revision
    unique (source_id, external_record_id, revision)
);

create index fight_members_user_id_idx on public.fight_members (user_id);
create index fight_members_selected_source_id_idx on public.fight_members (selected_source_id);
create index fights_owner_id_idx on public.fights (owner_id);
create index fights_state_window_idx on public.fights (state, starts_at, ends_at);
create index data_sources_user_id_idx on public.data_sources (user_id);
create index fight_invites_fight_id_idx on public.fight_invites (fight_id);
create index fight_invites_invited_user_id_idx on public.fight_invites (invited_user_id);
create index friendships_addressee_id_idx on public.friendships (addressee_id);
create index metric_observations_user_time_idx
  on private.metric_observations (user_id, metric, starts_at, ends_at);

-- ---------------------------------------------------------------------------
-- Profile on signup
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  generated_handle text;
begin
  generated_handle := 'user_' || substr(replace(new.id::text, '-', ''), 1, 12);
  insert into public.profiles (user_id, handle, display_name)
  values (
    new.id,
    generated_handle,
    coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      nullif(new.raw_user_meta_data->>'name', ''),
      'Fighter'
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Grants — clients never write fights, scores, sources, or invites.
-- token_hash is not granted.
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated, service_role;

grant select on public.profiles to authenticated;
grant update (display_name, avatar_path, time_zone) on public.profiles to authenticated;

grant select, insert on public.friendships to authenticated;
grant update (state) on public.friendships to authenticated;

grant select on public.fights to authenticated;
grant select on public.fight_members to authenticated;
grant select on public.data_sources to authenticated;
grant select (id, fight_id, invited_user_id, expires_at, revoked_at, accepted_at)
  on public.fight_invites to authenticated;

grant all on all tables in schema public to postgres, service_role;
grant all on all sequences in schema public to postgres, service_role;
grant all on all tables in schema private to postgres, service_role;
grant all on all sequences in schema private to postgres, service_role;

alter default privileges in schema private
  grant all on tables to postgres, service_role;
alter default privileges in schema public
  grant all on tables to postgres, service_role;

revoke all on table private.metric_observations from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.fights enable row level security;
alter table public.fight_members enable row level security;
alter table public.fight_invites enable row level security;
alter table public.data_sources enable row level security;
alter table private.metric_observations enable row level security;

alter table public.profiles force row level security;
alter table public.friendships force row level security;
alter table public.fights force row level security;
alter table public.fight_members force row level security;
alter table public.fight_invites force row level security;
alter table public.data_sources force row level security;
alter table private.metric_observations force row level security;

create policy profiles_select_visible
  on public.profiles
  for select
  to authenticated
  using (deleted_at is null);

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy friendships_select_involved
  on public.friendships
  for select
  to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

create policy friendships_insert_self
  on public.friendships
  for insert
  to authenticated
  with check (
    requester_id = (select auth.uid())
    and requester_id <> addressee_id
  );

create policy friendships_update_addressee
  on public.friendships
  for update
  to authenticated
  using (addressee_id = (select auth.uid()))
  with check (addressee_id = (select auth.uid()));

create policy fights_select_involved
  on public.fights
  for select
  to authenticated
  using (
    owner_id = (select auth.uid())
    or exists (
      select 1
      from public.fight_members as membership
      where membership.fight_id = fights.id
        and membership.user_id = (select auth.uid())
        and membership.state in ('invited', 'accepted')
    )
  );

create policy fight_members_select_self_or_accepted_peer
  on public.fight_members
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.fight_members as me
      where me.fight_id = fight_members.fight_id
        and me.user_id = (select auth.uid())
        and me.state = 'accepted'
    )
  );

create policy fight_invites_select_owner_or_invitee
  on public.fight_invites
  for select
  to authenticated
  using (
    invited_user_id = (select auth.uid())
    or exists (
      select 1
      from public.fights as fight
      where fight.id = fight_invites.fight_id
        and fight.owner_id = (select auth.uid())
    )
  );

create policy data_sources_select_own
  on public.data_sources
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- private.metric_observations: RLS on, no client policies. Next.js uses service_role.
