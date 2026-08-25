-- Phone writes its own Steps Fight rows so TestFlight works without Vercel.
-- Scores are still only your own rows. Peers read them. Nobody writes someone else's total.

alter table public.profiles
  add column if not exists handle_set_at timestamptz;

grant update (handle, handle_set_at) on public.profiles to authenticated;

create table public.step_days (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  day date not null,
  steps integer not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, day),
  constraint step_days_steps_nonnegative check (steps >= 0)
);

create index step_days_day_idx on public.step_days (day);

grant select, insert, update on public.step_days to authenticated;
grant insert, update on public.fights to authenticated;
grant insert, update on public.fight_members to authenticated;
grant insert, update on public.data_sources to authenticated;

alter table public.step_days enable row level security;
alter table public.step_days force row level security;

create function private.current_user_shares_accepted_fight(_other uuid)
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
    where me.user_id = auth.uid()
      and them.user_id = _other
      and me.state = 'accepted'
      and them.state = 'accepted'
  );
$$;

revoke all on function private.current_user_shares_accepted_fight(uuid) from public;
grant execute on function private.current_user_shares_accepted_fight(uuid) to authenticated;

create policy fights_insert_own
  on public.fights
  for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and metric = 'steps'
    and state in ('live', 'inviting', 'scheduled')
  );

create policy fights_update_owner_or_due
  on public.fights
  for update
  to authenticated
  using (
    owner_id = (select auth.uid())
    or (
      private.current_user_is_accepted_member(id)
      and ends_at < now()
    )
  )
  with check (
    owner_id = (select auth.uid())
    or (
      private.current_user_is_accepted_member(id)
      and ends_at < now()
      and state in ('final', 'awaiting_final_sync', 'cancelled')
    )
  );

create policy fight_members_insert_owner_or_self
  on public.fight_members
  for insert
  to authenticated
  with check (
    state in ('accepted', 'invited')
    and (
      user_id = (select auth.uid())
      or exists (
        select 1
        from public.fights as fight
        where fight.id = fight_id
          and fight.owner_id = (select auth.uid())
      )
    )
  );

create policy fight_members_update_own
  on public.fight_members
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy data_sources_insert_own
  on public.data_sources
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy data_sources_update_own
  on public.data_sources
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy step_days_select_self_or_fight
  on public.step_days
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.current_user_shares_accepted_fight(user_id)
  );

create policy step_days_insert_own
  on public.step_days
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy step_days_update_own
  on public.step_days
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy friendships_insert_self on public.friendships;

create policy friendships_insert_self
  on public.friendships
  for insert
  to authenticated
  with check (
    requester_id = (select auth.uid())
    and requester_id <> addressee_id
    and state in ('pending', 'accepted')
  );
