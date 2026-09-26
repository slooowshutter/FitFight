-- Durable account images outlive the short-lived provider request history.
create table private.ai_library_images (
    request_id uuid not null,
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    workflow text not null check (workflow in ('avatar', 'fitness', 'group_photo')),
    description text not null check (char_length(description) between 1 and 1000),
    stage text not null check (stage in ('image_url', 'resting', 'soft', 'average', 'fit', 'strong')),
    image_url text not null check (image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/'),
    created_at timestamptz not null default now(),
    primary key (request_id, stage),
    check ((workflow = 'fitness') = (stage <> 'image_url'))
);
create index ai_library_images_owner on private.ai_library_images (user_id, created_at desc);
alter table private.ai_library_images enable row level security;
revoke all on private.ai_library_images from public, anon, authenticated, service_role, fitfight_backend_reader;

alter table private.ai_requests add column description text not null default '';
alter table public.profiles add column companion_image_url text
    check (companion_image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/');
