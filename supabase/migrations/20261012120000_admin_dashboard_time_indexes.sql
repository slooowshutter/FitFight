begin;

set local lock_timeout = '5s';

-- The admin dashboard reads recent windows of these tables, which keep every row. Without an
-- index that starts with the time column, each of those reads scans the whole table.
create index if not exists activity_raw_steps_total_created_idx
    on private.activity_raw (created_at)
    where record_kind = 'total' and record_type = 'steps';
create index if not exists fight_score_snapshots_created_idx
    on private.fight_score_snapshots (created_at);
create index if not exists healthkit_sync_attempts_started_idx
    on private.healthkit_sync_attempts (started_at);

commit;
