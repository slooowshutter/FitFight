-- Comment @tags follow public.fight_post_tags.

create table public.fight_post_comment_tags (
    comment_id uuid not null references public.fight_post_comments (id) on delete cascade,
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (comment_id, user_id)
);

create index fight_post_comment_tags_user_idx
    on public.fight_post_comment_tags (user_id, created_at desc);

revoke all on table public.fight_post_comment_tags from public, anon, authenticated;
grant select on public.fight_post_comment_tags to authenticated, fitfight_backend_reader;
grant all on table public.fight_post_comment_tags to postgres, service_role;

alter table public.fight_post_comment_tags enable row level security;
alter table public.fight_post_comment_tags force row level security;

create policy fight_post_comment_tags_select_visible
    on public.fight_post_comment_tags
    for select
    to authenticated, fitfight_backend_reader
    using (
        exists (
            select 1
            from public.fight_post_comments as comment
            where comment.id = fight_post_comment_tags.comment_id
                and private.current_user_can_see_fight_post(comment.post_id)
        )
    );
