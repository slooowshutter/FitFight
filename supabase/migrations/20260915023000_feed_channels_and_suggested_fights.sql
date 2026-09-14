-- One post can appear in several fight feeds without duplicating the row.
-- Marc can flag a series as suggested for the New tab.

alter table public.fight_posts
  add column broadcast boolean not null default false;

create table public.fight_post_channels (
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  fight_id uuid not null references public.fights (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, fight_id)
);

create index fight_post_channels_fight_idx
  on public.fight_post_channels (fight_id, post_id);

alter table public.fight_series
  add column suggested boolean not null default false;

alter table public.fight_series
  add column suggested_at timestamptz;

create index fight_series_suggested_idx
  on public.fight_series (suggested_at desc)
  where suggested;

insert into public.fight_post_channels (post_id, fight_id)
select id, fight_id
from public.fight_posts
where fight_id is not null
on conflict do nothing;

-- Copies from one compose (same author, body, and second) become one post
-- with every fight attached, so comments and the root Feed stop splitting.
create temporary table fight_post_dupes (
  id uuid primary key,
  keeper_id uuid not null
) on commit drop;

insert into fight_post_dupes (id, keeper_id)
select id, keeper_id
from (
  select
    id,
    first_value(id) over (
      partition by author_id, body, date_trunc('second', created_at)
      order by id
    ) as keeper_id
  from public.fight_posts
  where audience = 'fight'
) as ranked
where id <> keeper_id;

insert into public.fight_post_channels (post_id, fight_id)
select dupes.keeper_id, channel.fight_id
from fight_post_dupes as dupes
join public.fight_post_channels as channel on channel.post_id = dupes.id
on conflict do nothing;

-- Move every comment in one shot. The same-post trigger would reject a
-- child whose parent still points at the duplicate post.
alter table public.fight_post_comments disable trigger fight_post_comments_same_post;

update public.fight_post_comments as comment
set post_id = dupes.keeper_id
from fight_post_dupes as dupes
where comment.post_id = dupes.id;

alter table public.fight_post_comments enable trigger fight_post_comments_same_post;

insert into public.fight_post_reactions (post_id, user_id, emoji, created_at)
select dupes.keeper_id, reaction.user_id, reaction.emoji, reaction.created_at
from fight_post_dupes as dupes
join public.fight_post_reactions as reaction on reaction.post_id = dupes.id
on conflict (post_id, user_id) do nothing;

delete from public.fight_post_reactions as reaction
using fight_post_dupes as dupes
where reaction.post_id = dupes.id;

insert into public.fight_post_tags (post_id, user_id, created_at)
select dupes.keeper_id, tag.user_id, tag.created_at
from fight_post_dupes as dupes
join public.fight_post_tags as tag on tag.post_id = dupes.id
on conflict (post_id, user_id) do nothing;

delete from public.fight_posts
where id in (select id from fight_post_dupes);

revoke all on table public.fight_post_channels from public, anon, authenticated;
grant select on public.fight_post_channels to authenticated, fitfight_backend_reader;
grant all on table public.fight_post_channels to postgres, service_role;

alter table public.fight_post_channels enable row level security;
alter table public.fight_post_channels force row level security;

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
        (
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

create policy fight_post_channels_select_visible
  on public.fight_post_channels
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(post_id));
