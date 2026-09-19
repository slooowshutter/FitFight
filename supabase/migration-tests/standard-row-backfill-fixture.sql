-- Disposable CI only, replayed immediately before the standard-column migration.
insert into auth.users (id, created_at) values
    ('92000000-0000-4000-8000-000000000001', '2026-08-25');
update public.profiles set companion_id = 'custom', companion_prompt = 'An otter with a blue scarf'
where user_id = '92000000-0000-4000-8000-000000000001';
insert into public.data_sources (id, user_id, provider, source_label, connection_route, connected_at)
values ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
    'apple_health', 'Apple Health', 'healthkit', '2026-08-26');
insert into public.step_days (user_id, day, steps, updated_at)
values ('92000000-0000-4000-8000-000000000001', '2026-09-01', 4321, '2026-09-02');
insert into private.account_preferences (user_id, language, appearance, updated_at)
values ('92000000-0000-4000-8000-000000000001', 'fr', 'dark', '2026-09-03');
insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
values ('94000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
    'Metadata backfill', 'live', now() - interval '1 day', now() + interval '1 day', 'UTC', 'highest_total', 'shared');
insert into public.fight_members (fight_id, user_id, state, accepted_at)
values ('94000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'accepted', now());

create schema row_columns_test;
create table row_columns_test.before_rows (table_name text, rows jsonb, primary key (table_name));
create table row_columns_test.before_keys as
select conrelid, conname, pg_get_constraintdef(oid) definition from pg_constraint
where connamespace in ('public'::regnamespace, 'private'::regnamespace) and contype in ('p', 'u', 'f');
create table row_columns_test.before_messages as select count(*) total from realtime.messages;
do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'public.profiles', 'public.fights', 'public.fight_members', 'public.data_sources', 'public.step_days',
        'private.account_preferences', 'private.companion_libraries', 'private.fight_membership_events',
        'private.fight_record_contexts', 'private.fight_participation_records'
    ] loop
        execute format('insert into row_columns_test.before_rows select %L, coalesce(jsonb_agg(to_jsonb(row)), ''[]''::jsonb) from %s row', table_name, table_name);
    end loop;
end;
$$;
