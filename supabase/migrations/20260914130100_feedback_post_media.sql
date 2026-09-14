-- Signed-in Users can attach photos, videos, or other files to Bugs & requests.
-- Writes stay on the TypeScript backend.

update storage.buckets
set allowed_mime_types = null
where id = 'user-media';

alter table public.media_objects
  drop constraint media_objects_content_type,
  drop constraint media_objects_kind_mime,
  drop constraint media_objects_kind_shape;

alter table public.media_objects
  add constraint media_objects_content_type check (
    char_length(content_type) between 3 and 200
    and content_type ~ '^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$'
  ),
  add constraint media_objects_kind_mime check (
    (kind = 'photo' and content_type in ('image/jpeg', 'image/png', 'image/webp') and byte_size <= 8388608)
    or (kind = 'video' and content_type in ('video/mp4', 'video/quicktime'))
    or (kind = 'file' and purpose = 'feedback')
  ),
  add constraint media_objects_kind_shape check (
    (kind = 'photo' and duration_ms is null)
    or (kind = 'video' and duration_ms between 1 and 180000)
    or (kind = 'file' and duration_ms is null)
  );

create table public.feedback_post_media (
  post_id uuid not null references public.feedback_posts (id) on delete cascade,
  media_id uuid not null references public.media_objects (id) on delete restrict,
  sort integer not null default 0,
  primary key (post_id, media_id),
  constraint feedback_post_media_sort check (sort between 0 and 7)
);

create unique index feedback_post_media_one_post
  on public.feedback_post_media (media_id);

create index feedback_post_media_post_idx
  on public.feedback_post_media (post_id, sort);

revoke all on table public.feedback_post_media from public, anon, authenticated;
grant select on public.feedback_post_media to authenticated, fitfight_backend_reader;
grant all on table public.feedback_post_media to postgres, service_role;

alter table public.feedback_post_media enable row level security;
alter table public.feedback_post_media force row level security;

create policy feedback_post_media_select_signed_in
  on public.feedback_post_media
  for select
  to authenticated, fitfight_backend_reader
  using (true);

drop policy media_objects_select_owner_or_shared on public.media_objects;
create policy media_objects_select_owner_or_shared
  on public.media_objects
  for select
  to authenticated, fitfight_backend_reader
  using (
    owner_id = (select auth.uid())
    or (
      status = 'ready'
      and (
        exists (
          select 1
          from public.profiles as profile
          where profile.avatar_media_id = media_objects.id
            and private.current_user_shares_accepted_fight(profile.user_id)
        )
        or exists (
          select 1
          from public.fight_post_media as attachment
          where attachment.media_id = media_objects.id
            and private.current_user_can_see_fight_post(attachment.post_id)
        )
        or exists (
          select 1
          from public.feedback_post_media as attachment
          where attachment.media_id = media_objects.id
        )
      )
    )
  );
