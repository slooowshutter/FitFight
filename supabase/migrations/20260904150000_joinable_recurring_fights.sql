-- Joinable fights (short code + live list) and rolling recurring series.
-- List and join stay server-owned. Clients cannot insert themselves onto a stranger's fight.

create type public.fight_visibility as enum (
  'invite_only',
  'joinable'
);

create table public.fight_series (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (user_id),
  join_code text,
  visibility public.fight_visibility not null default 'invite_only',
  recurring boolean not null default false,
  duration_seconds integer not null,
  name text not null,
  action_text text,
  time_zone text not null,
  paused_at timestamptz,
  current_fight_id uuid references public.fights (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint fight_series_duration_positive check (duration_seconds > 0),
  constraint fight_series_join_code_format check (
    join_code is null
    or join_code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{4}$'
  ),
  constraint fight_series_joinable_has_code check (
    visibility = 'invite_only'
    or join_code is not null
  )
);

create unique index fight_series_join_code_idx
  on public.fight_series (join_code)
  where join_code is not null;

create index fight_series_owner_id_idx on public.fight_series (owner_id);
create index fight_series_current_fight_id_idx on public.fight_series (current_fight_id);

create table public.fight_series_members (
  series_id uuid not null references public.fight_series (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id),
  state public.fight_member_state not null default 'accepted',
  joined_at timestamptz not null default now(),
  primary key (series_id, user_id)
);

create index fight_series_members_user_id_idx on public.fight_series_members (user_id);

alter table public.fights
  add column series_id uuid references public.fight_series (id) on delete set null;

create unique index fights_series_starts_at_idx
  on public.fights (series_id, starts_at)
  where series_id is not null;

create index fights_series_id_idx on public.fights (series_id);

create table private.fight_join_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  client_ip text,
  created_at timestamptz not null default now()
);

create index fight_join_attempts_user_time_idx
  on private.fight_join_attempts (user_id, created_at desc);
create index fight_join_attempts_ip_time_idx
  on private.fight_join_attempts (client_ip, created_at desc);

alter table public.fight_series enable row level security;
alter table public.fight_series force row level security;
alter table public.fight_series_members enable row level security;
alter table public.fight_series_members force row level security;
alter table private.fight_join_attempts enable row level security;
alter table private.fight_join_attempts force row level security;

grant select on public.fight_series to authenticated;
grant select on public.fight_series_members to authenticated;

create function private.current_user_can_see_series(_series_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_series as series
    where series.id = _series_id
      and series.owner_id = auth.uid()
  )
  or exists (
    select 1
    from public.fight_series_members as member
    where member.series_id = _series_id
      and member.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.fights as fight
    join public.fight_members as member
      on member.fight_id = fight.id
    where fight.series_id = _series_id
      and member.user_id = auth.uid()
  );
$$;

revoke all on function private.current_user_can_see_series(uuid) from public;
grant execute on function private.current_user_can_see_series(uuid) to authenticated;

create policy fight_series_select_involved
  on public.fight_series
  for select
  to authenticated
  using (private.current_user_can_see_series(id));

create policy fight_series_members_select_involved
  on public.fight_series_members
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.current_user_can_see_series(series_id)
  );

drop policy fight_members_insert_owner_or_self on public.fight_members;

create policy fight_members_insert_owner
  on public.fight_members
  for insert
  to authenticated
  with check (
    state in ('accepted', 'invited')
    and exists (
      select 1
      from public.fights as fight
      where fight.id = fight_id
        and fight.owner_id = (select auth.uid())
    )
  );
