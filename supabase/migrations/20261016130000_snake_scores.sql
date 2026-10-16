begin;

-- One row per finished Snake game, played while a custom character is drawn. The highest score is the record
-- every player sees. A 15 by 15 board holds at most 222 points (225 cells, starting length 3). The snake moves at
-- most once every 80 ms, so a score needs at least 80 ms of play per point.
create table private.snake_scores (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    score integer not null check (score between 0 and 222),
    duration_ms integer not null check (duration_ms between 0 and 86400000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint snake_scores_playable check (duration_ms >= score * 80)
);
create index snake_scores_player_idx on private.snake_scores (user_id, created_at desc);
create index snake_scores_score_idx on private.snake_scores (score desc);
alter table private.snake_scores enable row level security;
revoke all on private.snake_scores from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.snake_scores
    for each row execute function private.maintain_row_timestamps();

commit;
