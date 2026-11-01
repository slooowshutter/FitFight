begin;
set local lock_timeout = '5s';

-- One row per model call of the FitFight AI workflows (web/lib/ai/workflows.ts), which replace the Blend runs.
-- A retried call writes one row per attempt. run_id is the Workflow SDK run: ai_requests.run_handle->>'runId'
-- or fight_group_images.run_id. App-run rows follow their owner's account deletion; otherwise rows are kept forever.
create table private.ai_steps (
    id uuid primary key default gen_random_uuid(),
    request_id uuid references private.ai_requests (id) on delete cascade,
    run_id text not null,
    workflow text not null,
    step text not null,
    step_id text not null,
    attempt integer not null check (attempt >= 1),
    kind text not null check (kind in ('text', 'image')),
    provider text not null check (provider in ('openrouter', 'azure')),
    model text not null,
    -- The exact model version that answered, and who ran it: the company behind OpenRouter, or the Azure region.
    model_used text,
    upstream text,
    status text not null check (status in ('completed', 'failed')),
    error text,
    started_at timestamptz not null,
    duration_ms integer not null check (duration_ms >= 0),
    -- Text only: from the call to the first streamed token.
    first_token_ms integer check (first_token_ms >= 0),
    input_tokens integer,
    output_tokens integer,
    reasoning_tokens integer,
    cached_tokens integer,
    -- Dollars. provider: what OpenRouter charged. price_list: an Azure drawing, paid with Azure credits, at OpenAI's
    -- list price for its tokens (web/lib/types/ai/step.ts).
    cost_usd numeric(14, 8) check (cost_usd >= 0),
    cost_source text check (cost_source in ('provider', 'price_list')),
    -- The resolved prompt, picture links and settings sent, and the text or picture link returned.
    input jsonb not null check (jsonb_typeof(input) = 'object'),
    output jsonb,
    code_version text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (request_id is not null or workflow in ('trail', 'raceStart'))
);
create index ai_steps_request on private.ai_steps (request_id);
create index ai_steps_run on private.ai_steps (run_id, started_at);
create index ai_steps_started on private.ai_steps (started_at);
alter table private.ai_steps enable row level security;
revoke all on private.ai_steps from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.ai_steps
    for each row execute function private.maintain_row_timestamps();

-- The production admin dashboard's read-only user (docs/backend.md) reads the AI section.
do $$
begin
    if exists (select from pg_roles where rolname = 'fitfight_analytics') then
        grant select on private.ai_steps to fitfight_analytics;
    end if;
end
$$;

-- One row per drawing started on an Azure region, so each region stays under its per-minute limit
-- (claimAzureImageSlot counts the last 60 seconds). Rows are kept forever.
create table private.ai_image_slots (
    id uuid primary key default gen_random_uuid(),
    region text not null,
    run_id text not null,
    step_id text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index ai_image_slots_recent on private.ai_image_slots (region, created_at);
alter table private.ai_image_slots enable row level security;
revoke all on private.ai_image_slots from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.ai_image_slots
    for each row execute function private.maintain_row_timestamps();

-- FitFight's own pictures. Public like Blend's output: each path holds the run and step ids. Only the backend
-- writes. Saved pictures keep their links forever.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-images', 'ai-images', true, 52428800, array['image/png']::text[])
on conflict (id) do update
set public = true,
    file_size_limit = 52428800,
    allowed_mime_types = array['image/png']::text[];

-- Saved pictures may now come from FitFight's bucket on staging or production, as well as from Blend.
alter table private.ai_library_images drop constraint ai_library_images_image_url_check;
alter table private.ai_library_images add constraint ai_library_images_image_url_check check (
    image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/'
    or image_url ~ '^https://(zstzbfocunthczzubggz|pvqntpteehdvhqyctwum)\.supabase\.co/storage/v1/object/public/ai-images/'
);
alter table public.profiles drop constraint profiles_companion_image_url_check;
alter table public.profiles add constraint profiles_companion_image_url_check check (
    companion_image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/'
    or companion_image_url ~ '^https://(zstzbfocunthczzubggz|pvqntpteehdvhqyctwum)\.supabase\.co/storage/v1/object/public/ai-images/'
);
alter table private.fight_group_images drop constraint fight_group_images_image_url_check;
alter table private.fight_group_images add constraint fight_group_images_image_url_check check (
    image_url ~ '^https://(supabase|cdn)\.tryblend\.ai/'
    or image_url ~ '^https://(zstzbfocunthczzubggz|pvqntpteehdvhqyctwum)\.supabase\.co/storage/v1/object/public/ai-images/'
);

commit;
