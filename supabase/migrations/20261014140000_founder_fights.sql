-- Founder fights: each user may start one repeating 1v1 Steps series against the founder.
-- The host (the founder) is an accepted member of every round, so older apps show a normal
-- 1v1. The backend scores the host from his stored daily Steps; his phone never uploads a
-- total for these rounds, and a founder fight creates no social relationship.

alter table public.fight_series
    add column host_id uuid references public.profiles (user_id);

alter table public.fights
    add column host_id uuid references public.profiles (user_id);

comment on column public.fight_series.host_id is
    'Founder fight host. Scored by the backend from stored daily Steps and left out of his own syncs, snapshot, pushes, and social surfaces.';
comment on column public.fights.host_id is
    'Copied from fight_series.host_id for every round, so per-fight filters need no series join.';

create unique index fight_series_owner_host_idx
    on public.fight_series (owner_id, host_id)
    where host_id is not null;

create index fights_host_id_idx
    on public.fights (host_id)
    where host_id is not null;

-- A host is not pinged for founder rounds; every other recipient is unchanged.
create or replace function private.broadcast_fight_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed_fights uuid[];
    changed_users uuid[] := '{}';
    recipient uuid;
begin
    if tg_table_name = 'fights' then
        select array_agg(n.id) into changed_fights
        from new_rows n join old_rows o using (id)
        where (to_jsonb(n) - 'updated_at') is distinct from (to_jsonb(o) - 'updated_at');
    elsif tg_op = 'INSERT' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from new_rows;
    elsif tg_op = 'DELETE' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from old_rows;
    else
        select array_agg(n.fight_id), array_agg(n.user_id) into changed_fights, changed_users
        from new_rows n join old_rows o using (fight_id, user_id)
        where (to_jsonb(n) - 'updated_at') is distinct from (to_jsonb(o) - 'updated_at');
    end if;

    -- Statement triggers deduplicate participants when a sync reranks several rows.
    for recipient in
        select m.user_id from public.fight_members m
        join public.fights f on f.id = m.fight_id
        where m.fight_id = any(changed_fights) and m.state in ('accepted', 'invited', 'deferred')
            and m.user_id is distinct from f.host_id
        union
        select f.owner_id from public.fights f where f.id = any(changed_fights)
        union
        select changed.user_id from unnest(changed_users) as changed (user_id)
        where not exists (
            select 1 from public.fights f
            where f.id = any(changed_fights) and f.host_id = changed.user_id
        )
    loop
        perform realtime.send('{}'::jsonb, 'fights_changed', 'fitfight:fights:' || recipient::text, true);
    end loop;
    return null;
end;
$$;

-- Sharing a founder round does not make Main posts visible in either direction.
create or replace function private.current_user_can_see_fight_post(_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.fight_posts as post
        where post.id = _post_id
            and (
                post.app_wide
                or (
                    post.audience = 'main'
                    and (
                        post.author_id = (select auth.uid())
                        or exists (
                            select 1
                            from public.fight_members as me
                            join public.fight_members as them
                                on them.fight_id = me.fight_id
                            join public.fights as shared
                                on shared.id = me.fight_id
                            where me.user_id = (select auth.uid())
                                and them.user_id = post.author_id
                                and me.state in ('accepted', 'deferred')
                                and them.state in ('accepted', 'deferred')
                                and shared.host_id is null
                        )
                    )
                )
                or (
                    post.audience = 'fight'
                    and (
                        private.current_user_is_roster_member(post.fight_id)
                        or exists (
                            select 1
                            from public.fights as posted
                            join public.fights as sibling
                                on sibling.series_id = posted.series_id
                            where posted.id = post.fight_id
                                and posted.series_id is not null
                                and private.current_user_is_roster_member(sibling.id)
                        )
                    )
                )
                or exists (
                    select 1
                    from public.fight_post_channels as channel
                    join public.fights as posted
                        on posted.id = channel.fight_id
                    where channel.post_id = post.id
                        and (
                            private.current_user_is_roster_member(channel.fight_id)
                            or (
                                posted.series_id is not null
                                and exists (
                                    select 1
                                    from public.fights as sibling
                                    where sibling.series_id = posted.series_id
                                        and private.current_user_is_roster_member(sibling.id)
                                )
                            )
                        )
                )
            )
    );
$$;

-- Feed reload pings follow the same rule: a host is not pinged for his founder rounds.
create or replace function private.broadcast_feed_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed jsonb;
    changed_post_id uuid;
    changed_fight_id uuid;
    changed_app_wide boolean := false;
    recipient uuid;
begin
    if tg_op = 'DELETE' then
        changed := to_jsonb(old);
    else
        changed := to_jsonb(new);
    end if;
    if tg_table_name = 'fight_posts' then
        changed_post_id := (changed->>'id')::uuid;
        changed_app_wide := (changed->>'app_wide')::boolean;
    else
        changed_post_id := (changed->>'post_id')::uuid;
        select p.app_wide into changed_app_wide
        from public.fight_posts p where p.id = changed_post_id;
    end if;
    changed_fight_id := (changed->>'fight_id')::uuid;

    for recipient in
        with affected_fights as (
            select changed_fight_id as id
            union
            select p.fight_id from public.fight_posts p where p.id = changed_post_id
            union
            select c.fight_id from public.fight_post_channels c where c.post_id = changed_post_id
        ), visible_fights as (
            select f.id from public.fights f
            where f.id in (select a.id from affected_fights a)
                or f.series_id in (
                    select original.series_id from public.fights original
                    where original.id in (select a.id from affected_fights a)
                )
        )
        select m.user_id from public.fight_members m
        join public.fights f on f.id = m.fight_id
        where m.fight_id in (select v.id from visible_fights v)
            and m.state in ('accepted', 'deferred', 'invited')
            and m.user_id is distinct from f.host_id
        union
        select p.user_id from public.profiles p
        where changed_app_wide and p.deleted_at is null
        union
        select (changed->>'user_id')::uuid
        where tg_table_name = 'fight_membership_events'
            and not exists (
                select 1 from public.fights f
                where f.id = changed_fight_id and f.host_id = (changed->>'user_id')::uuid
            )
        union
        select (changed->>'blocker_id')::uuid where tg_table_name = 'feed_blocks'
        union
        select (changed->>'blocked_id')::uuid where tg_table_name = 'feed_blocks'
    loop
        if recipient is not null then
            perform realtime.send('{}'::jsonb, 'feed_changed', 'fitfight:fights:' || recipient::text, true);
        end if;
    end loop;
    return null;
end;
$$;
