-- Phone still writes fights, memberships, and step_days.
-- Stop joining any fight, moving a membership, or rewriting a due fight's name.

revoke update on public.fights from authenticated;
grant update (state) on public.fights to authenticated;

revoke update on public.fight_members from authenticated;
grant update (state, accepted_at, current_value) on public.fight_members to authenticated;

drop policy fight_members_insert_owner_or_self on public.fight_members;

create policy fight_members_insert_owner
  on public.fight_members
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.fights as fight
      where fight.id = fight_id
        and fight.owner_id = (select auth.uid())
    )
    and (
      (user_id = (select auth.uid()) and state = 'accepted')
      or (user_id <> (select auth.uid()) and state = 'invited')
    )
  );
