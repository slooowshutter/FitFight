begin;

-- One WHOOP login per person. WHOOP records themselves are stored raw in private.activity_raw
-- under a data_sources row with provider 'whoop'. Tokens are one AES-256-GCM sealed JSON object
-- (access and refresh token), keyed by WHOOP_TOKEN_ENCRYPTION_KEY.
create table private.whoop_connections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references public.profiles (user_id) on delete cascade,
    whoop_user_id bigint unique,
    oauth_state text unique,
    oauth_state_expires_at timestamptz,
    tokens_ciphertext text,
    tokens_iv text,
    tokens_tag text,
    access_token_expires_at timestamptz,
    connected_at timestamptz,
    last_synced_at timestamptz,
    history_synced_at timestamptz,
    last_error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint whoop_connections_tokens check (
        (tokens_ciphertext is null) = (tokens_iv is null)
        and (tokens_iv is null) = (tokens_tag is null)
        and (tokens_ciphertext is null) = (access_token_expires_at is null)
    )
);
alter table private.whoop_connections enable row level security;
revoke all on private.whoop_connections from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.whoop_connections
    for each row execute function private.maintain_row_timestamps();

-- The production admin dashboard's read-only user (docs/status.md) sees sync state, never tokens.
do $$
begin
    if exists (select from pg_roles where rolname = 'fitfight_analytics') then
        grant select (user_id, access_token_expires_at, connected_at, last_synced_at, history_synced_at, last_error)
            on private.whoop_connections to fitfight_analytics;
    end if;
end
$$;

commit;
