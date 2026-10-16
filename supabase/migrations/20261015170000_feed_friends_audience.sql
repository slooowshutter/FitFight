-- Posts can go to the author's friends. A post with to_friends is visible to the author's
-- accepted friends on Feed, in addition to the fights it was posted in. A friends-only post
-- keeps the existing Main shape (audience 'main', no fight) and is not visible through the
-- legacy Main rule. Additive: every existing row keeps to_friends = false.

alter table public.fight_posts
    add column to_friends boolean not null default false;

comment on column public.fight_posts.to_friends is
    'Visible to the author''s accepted friends on Feed, besides any fights in fight_post_channels.';

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
                    post.to_friends
                    and (
                        post.author_id = (select auth.uid())
                        or (
                            exists (
                                select 1
                                from private.profile_friendships as friendship
                                where friendship.user_low = least((select auth.uid()), post.author_id)
                                    and friendship.user_high = greatest((select auth.uid()), post.author_id)
                                    and friendship.state = 'accepted'
                            )
                            and not exists (
                                select 1
                                from private.feed_blocks as blocked
                                where (blocked.blocker_id = post.author_id and blocked.blocked_id = (select auth.uid()))
                                    or (blocked.blocker_id = (select auth.uid()) and blocked.blocked_id = post.author_id)
                            )
                        )
                    )
                )
                or (
                    post.audience = 'main'
                    and not post.to_friends
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

-- A friends post outlives its last fight like a Public post: it moves to the friends-only
-- Main shape instead of cascading away with the fight.
create or replace function private.rehome_fight_posts_before_fight_delete()
returns trigger
language plpgsql
as $$
begin
    update public.fight_posts as post
    set fight_id = remaining.fight_id
    from (
        select distinct on (channel.post_id)
            channel.post_id,
            channel.fight_id
        from public.fight_post_channels as channel
        where channel.fight_id is distinct from old.id
        order by channel.post_id, channel.fight_id
    ) as remaining
    where post.fight_id = old.id
        and remaining.post_id = post.id;

    update public.fight_posts
    set audience = 'main',
            fight_id = null
    where fight_id = old.id
        and (broadcast or to_friends);

    return old;
end;
$$;

-- Feed reload pings also reach the author and the author's friends for a friends post.
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
    changed_to_friends boolean := false;
    changed_author_id uuid;
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
        changed_to_friends := coalesce((changed->>'to_friends')::boolean, false);
        changed_author_id := (changed->>'author_id')::uuid;
    else
        changed_post_id := (changed->>'post_id')::uuid;
        select p.app_wide, p.to_friends, p.author_id
        into changed_app_wide, changed_to_friends, changed_author_id
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
        select changed_author_id where changed_to_friends
        union
        select case when friendship.user_low = changed_author_id then friendship.user_high else friendship.user_low end
        from private.profile_friendships friendship
        where changed_to_friends
            and friendship.state = 'accepted'
            and (friendship.user_low = changed_author_id or friendship.user_high = changed_author_id)
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
