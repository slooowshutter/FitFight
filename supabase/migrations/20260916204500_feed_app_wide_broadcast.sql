-- App-wide Marc broadcast posts. One row on Feed for every signed-in user.
-- Writes stay on the TypeScript backend.

alter table public.fight_posts
    add column app_wide boolean not null default false;

alter table public.fight_posts
    add constraint fight_posts_app_wide_shape
    check (not app_wide or (audience = 'main' and fight_id is null));

create index fight_posts_app_wide_created_idx
    on public.fight_posts (created_at desc, id desc)
    where app_wide;

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
                            where me.user_id = (select auth.uid())
                                and them.user_id = post.author_id
                                and me.state in ('accepted', 'deferred')
                                and them.state in ('accepted', 'deferred')
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
