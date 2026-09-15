-- Production has not applied this migration yet. App Store build 113 still creates
-- fights and answers invitations directly. Preserve only its columns and transitions.
-- Already-migrated staging keeps its existing server-only writes.
revoke insert, update, delete
    on public.fights, public.fight_members, public.data_sources
    from public, anon, authenticated;

drop policy if exists fights_insert_own on public.fights;
drop policy if exists fights_update_owner_or_due on public.fights;
drop policy if exists fight_members_insert_owner on public.fight_members;
drop policy if exists fight_members_update_own on public.fight_members;
drop policy if exists data_sources_insert_own on public.data_sources;
drop policy if exists data_sources_update_own on public.data_sources;

grant insert (owner_id, name, state, starts_at, ends_at, time_zone, metric,
    outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text)
    on public.fights to authenticated;
grant insert (fight_id, user_id, state, accepted_at)
    on public.fight_members to authenticated;
grant update (state, accepted_at) on public.fight_members to authenticated;

create policy fights_insert_legacy_owner on public.fights
    for insert to authenticated
    with check (
        owner_id = (select auth.uid()) and state = 'live' and metric = 'steps'
        and outcome_rule = 'highest_total' and stake_kind = 'action'
    );

create policy fight_members_insert_legacy_owner on public.fight_members
    for insert to authenticated
    with check (
        ((user_id = (select auth.uid()) and state = 'accepted' and accepted_at is not null)
            or (user_id <> (select auth.uid()) and state = 'invited' and accepted_at is null))
        and exists (
            select 1 from public.fights as fight
            where fight.id = fight_id and fight.owner_id = (select auth.uid())
                and fight.state = 'live' and fight.ends_at > now()
        )
    );

create policy fight_members_update_legacy_invitee on public.fight_members
    for update to authenticated
    using (user_id = (select auth.uid()) and state = 'invited')
    with check (
        user_id = (select auth.uid())
        and ((state = 'accepted' and accepted_at is not null) or state = 'declined')
    );
