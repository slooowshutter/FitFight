create table private.fight_post_comment_likes (
    comment_id uuid not null references public.fight_post_comments (id) on delete cascade,
    post_id uuid not null references public.fight_posts (id) on delete cascade,
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    primary key (comment_id, user_id)
);

create index fight_post_comment_likes_user_idx
    on private.fight_post_comment_likes (user_id);
create index fight_post_comment_likes_post_idx
    on private.fight_post_comment_likes (post_id);

alter table private.fight_post_comment_likes enable row level security;
alter table private.fight_post_comment_likes force row level security;
revoke all on private.fight_post_comment_likes from public, anon, authenticated;
grant all on private.fight_post_comment_likes to postgres, service_role;

create trigger fight_post_comment_likes_broadcast_feed
after insert or delete on private.fight_post_comment_likes
for each row execute function private.broadcast_feed_changes();
