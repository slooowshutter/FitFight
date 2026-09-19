begin;

set local lock_timeout = '5s';

-- Metadata backfills must not replay membership history, companion capture, or broadcasts.
-- This setting is transaction-local; other sessions keep their normal triggers and RLS.
set local session_replication_role = replica;

create function private.maintain_row_timestamps()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    -- Preserve explicit timestamps from existing writers and historical imports.
    if new.updated_at is not distinct from old.updated_at then
        new.updated_at := statement_timestamp();
    end if;
    return new;
end;
$$;

revoke all on function private.maintain_row_timestamps() from public, anon, authenticated;

do $$
declare
    target record;
begin
    -- Existing keys remain in place for foreign keys, legacy clients, and ON CONFLICT.
    -- A generated ID preserves an existing single-row identity without a second UUID.
    for target in select * from (values
        ('private.account_preferences', 'user_id', 'updated_at', null),
        ('private.apple_sign_in_tokens', 'user_id', 'updated_at', null),
        ('private.companion_libraries', 'user_id', 'now()', 'now()'),
        ('private.device_installations', null, 'now()', 'now()'),
        ('private.feed_blocks', 'gen_random_uuid()', null, 'now()'),
        ('private.feedback_blocks', 'gen_random_uuid()', null, 'now()'),
        ('private.feedback_post_reports', null, null, 'now()'),
        ('private.fight_admin_actions', null, null, 'now()'),
        ('private.fight_join_attempts', null, null, 'now()'),
        ('private.fight_membership_events', null, 'now()', 'now()'),
        ('private.fight_participation_records', 'history_id', 'now()', 'now()'),
        ('private.fight_post_comment_reports', null, null, 'now()'),
        ('private.fight_post_reports', null, null, 'now()'),
        ('private.fight_record_contexts', 'fight_id', 'captured_at', 'now()'),
        ('private.fight_score_snapshots', null, null, 'now()'),
        ('private.healthkit_activity_days', 'gen_random_uuid()', 'updated_at', null),
        ('private.healthkit_step_sample_deletions', 'gen_random_uuid()', 'first_received_at', 'last_received_at'),
        ('private.healthkit_step_samples', 'gen_random_uuid()', 'first_received_at', 'last_received_at'),
        ('private.healthkit_step_source_days', 'gen_random_uuid()', 'updated_at', null),
        ('private.healthkit_step_syncs', 'user_id', 'now()', 'last_success_at'),
        ('private.healthkit_sync_attempts', 'gen_random_uuid()', 'received_at', 'now()'),
        ('private.healthkit_sync_diagnostics', 'gen_random_uuid()', 'updated_at', null),
        ('private.healthkit_workouts', 'gen_random_uuid()', 'updated_at', null),
        ('private.metric_observations', null, null, 'now()'),
        ('private.notification_deliveries', null, 'sent_at', 'now()'),
        ('private.notification_intents', null, null, 'now()'),
        ('private.notification_preferences', 'user_id', 'updated_at', null),
        ('private.profile_blocks', 'gen_random_uuid()', null, 'now()'),
        ('private.profile_event_totals', 'gen_random_uuid()', 'now()', 'now()'),
        ('private.profile_events', 'gen_random_uuid()', null, 'now()'),
        ('private.profile_friendships', 'gen_random_uuid()', null, 'now()'),
        ('private.profile_lookup_attempts', null, null, 'now()'),
        ('private.profile_reports', 'gen_random_uuid()', null, 'now()'),
        ('private.profile_settings', 'user_id', 'updated_at', null),
        ('private.provider_events', null, 'received_at', 'now()'),
        ('private.provider_uploads', 'upload_id', 'issued_at', null),
        ('private.referrals', 'referred_user_id', null, 'now()'),
        ('private.rivalry_artworks', null, null, 'now()'),
        ('private.server_error_logs', null, null, 'now()'),
        ('public.data_sources', null, 'connected_at', 'now()'),
        ('public.feedback_comments', null, null, 'now()'),
        ('public.feedback_post_media', 'gen_random_uuid()', 'now()', 'now()'),
        ('public.feedback_posts', null, null, 'now()'),
        ('public.feedback_votes', 'gen_random_uuid()', null, 'now()'),
        ('public.fight_invites', null, 'now()', 'now()'),
        ('public.fight_members', 'gen_random_uuid()', 'now()', 'now()'),
        ('public.fight_post_channels', 'gen_random_uuid()', null, 'now()'),
        ('public.fight_post_comments', null, null, 'now()'),
        ('public.fight_post_media', 'gen_random_uuid()', 'now()', 'now()'),
        ('public.fight_post_reactions', 'gen_random_uuid()', null, 'now()'),
        ('public.fight_post_tags', 'gen_random_uuid()', null, 'now()'),
        ('public.fight_posts', null, null, 'now()'),
        ('public.fight_series', null, null, 'now()'),
        ('public.fight_series_members', 'gen_random_uuid()', 'joined_at', 'now()'),
        ('public.fights', null, null, 'now()'),
        ('public.friendships', 'gen_random_uuid()', null, 'now()'),
        ('public.media_objects', null, null, 'now()'),
        ('public.metric_days', 'gen_random_uuid()', 'updated_at', null),
        ('public.profiles', 'user_id', 'coalesce((select created_at from auth.users where auth.users.id = public.profiles.user_id), now())', 'now()'),
        ('public.step_days', 'gen_random_uuid()', 'updated_at', null)
    ) as tables(table_name, id_source, created_source, updated_source)
    loop
        if target.id_source = 'gen_random_uuid()' then
            execute format('alter table %s add column id uuid not null default gen_random_uuid() unique', target.table_name);
        elsif target.id_source is not null then
            -- The source key already enforces uniqueness. A second unique index can
            -- defeat legacy ON CONFLICT targets during concurrent inserts.
            execute format('alter table %s add column id uuid generated always as (%I) stored not null', target.table_name, target.id_source);
            execute format('create index on %s (id)', target.table_name);
            execute format('comment on column %s.id is %L', target.table_name,
                'Stable row identity. Generated from ' || target.id_source || ' while existing writers and keys remain supported.');
        end if;

        if target.created_source is not null then
            execute format('alter table %s add column created_at timestamptz', target.table_name);
            execute format('update %s set created_at = %s', target.table_name, target.created_source);
            execute format('alter table %s alter column created_at set default now(), alter column created_at set not null', target.table_name);
            execute format('comment on column %s.created_at is %L', target.table_name,
                'Row creation time for new rows. Historical backfill: ' || target.created_source ||
                '. A prior updated_at is only a retained observation; now() means migration initialization, not recovered creation history.');
        end if;

        if target.updated_source is not null then
            execute format('alter table %s add column updated_at timestamptz', target.table_name);
            execute format('update %s set updated_at = %s', target.table_name, target.updated_source);
            execute format('alter table %s alter column updated_at set default now(), alter column updated_at set not null', target.table_name);
            execute format('comment on column %s.updated_at is %L', target.table_name,
                'Last row update. Historical backfill: ' || target.updated_source ||
                '. now() records migration initialization when the previous update time was not stored.');
        end if;

        execute format('create trigger maintain_row_timestamps before update on %s for each row execute function private.maintain_row_timestamps()', target.table_name);
    end loop;
end;
$$;

comment on column public.profiles.user_id is
    'Legacy signup, foreign-key, and direct-client compatibility key. Backend profile reads use id; v1 still returns user_id. Remove only in a separate compatibility cutoff.';

-- Timestamp-only member writes must not cause new Fight invalidations.
create or replace function private.broadcast_fight_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed_fights uuid[];
    changed_users uuid[] := '{}';
    recipient uuid;
begin
    if tg_table_name = 'fights' then
        select array_agg(n.id) into changed_fights
        from new_rows n join old_rows o using (id)
        where (to_jsonb(n) - 'updated_at') is distinct from (to_jsonb(o) - 'updated_at');
    elsif tg_op = 'INSERT' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from new_rows;
    elsif tg_op = 'DELETE' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from old_rows;
    else
        select array_agg(n.fight_id), array_agg(n.user_id) into changed_fights, changed_users
        from new_rows n join old_rows o using (fight_id, user_id)
        where (to_jsonb(n) - 'updated_at') is distinct from (to_jsonb(o) - 'updated_at');
    end if;

    -- Statement triggers deduplicate participants when a sync reranks several rows.
    for recipient in
        select m.user_id from public.fight_members m
        where m.fight_id = any(changed_fights) and m.state in ('accepted', 'invited', 'deferred')
        union
        select f.owner_id from public.fights f where f.id = any(changed_fights)
        union
        select unnest(changed_users)
    loop
        perform realtime.send('{}'::jsonb, 'fights_changed', 'fitfight:fights:' || recipient::text, true);
    end loop;
    return null;
end;
$$;

set local session_replication_role = origin;

commit;
