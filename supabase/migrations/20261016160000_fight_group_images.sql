begin;
set local lock_timeout = '5s';

-- One row per group image the backend makes for a fight (web/lib/domain/fight-images). A row waits an
-- hour after the fight's runners or companions change, runs on Blend, and ends ready, failed or cancelled.
-- A new round of a repeating fight with the same runners and companions gets a ready row reusing the last
-- image at once (attempt_log names the source). Rows are kept forever; the app shows the newest ready image.
create table private.fight_group_images (
    id uuid primary key default gen_random_uuid(),
    fight_id uuid not null references public.fights (id) on delete cascade,
    status text not null default 'waiting'
        check (status in ('waiting', 'running', 'ready', 'failed', 'cancelled')),
    due_at timestamptz not null,
    started_at timestamptz,
    finished_at timestamptz,
    -- md5 of the accepted runners and their companions when the image started; a new image waits for a change.
    cast_key text,
    layout text check (layout in ('trail', 'race_start')),
    runners jsonb check (runners is null or jsonb_typeof(runners) = 'array'),
    workflow_id text,
    inputs jsonb,
    run_id text,
    attempts integer not null default 0 check (attempts between 0 and 10),
    attempt_log jsonb not null default '[]'::jsonb check (jsonb_typeof(attempt_log) = 'array'),
    image_url text check (image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/'),
    error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create unique index fight_group_images_one_open
    on private.fight_group_images (fight_id) where status in ('waiting', 'running');
create index fight_group_images_fight_latest
    on private.fight_group_images (fight_id, finished_at desc) where status = 'ready';
create index fight_group_images_due on private.fight_group_images (due_at) where status = 'waiting';
create index fight_group_images_started on private.fight_group_images (started_at);
alter table private.fight_group_images enable row level security;
revoke all on private.fight_group_images from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.fight_group_images
    for each row execute function private.maintain_row_timestamps();

-- The fight snapshot reads the newest ready image of each fight the caller can see.
grant select (fight_id, status, image_url, finished_at) on private.fight_group_images to fitfight_backend_reader;
create policy fight_group_images_backend_visible
    on private.fight_group_images for select to fitfight_backend_reader
    using (status = 'ready' and private.current_user_can_see_fight(fight_id));

-- Reference sheets Blend reads while drawing: one grid of portraits per image, captioned with each
-- companion's name. Only the backend writes and signs them; no client policy exists.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fight-group-references', 'fight-group-references', false, 20971520, array['image/png']::text[])
on conflict (id) do update
set public = false,
    file_size_limit = 20971520,
    allowed_mime_types = array['image/png']::text[];

commit;
