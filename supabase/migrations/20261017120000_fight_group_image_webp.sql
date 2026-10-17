begin;
set local lock_timeout = '5s';

-- A 1200-pixel WebP copy of each ready group image (about 300 KB against Blend's 2-3 MB PNG), stored in our
-- own public bucket so the CDN keeps it. The snapshot serves it ahead of image_url, which stays as the source.
alter table private.fight_group_images add column webp_url text;
grant select (webp_url) on private.fight_group_images to fitfight_backend_reader;

-- Public like Blend's own output: each path is the image's random id. Only the backend writes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fight-group-images', 'fight-group-images', true, 5242880, array['image/webp']::text[])
on conflict (id) do update
set public = true,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/webp']::text[];

commit;
