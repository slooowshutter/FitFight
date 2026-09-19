begin;
select no_plan();

select is((select id from public.profiles where user_id = '92000000-0000-4000-8000-920000000001'),
    '92000000-0000-4000-8000-920000000001'::uuid, 'existing profiles retain their Auth identity');
select is((select created_at from public.profiles where id = '92000000-0000-4000-8000-920000000001'),
    '2026-08-25'::timestamptz, 'profile backfill uses recorded signup time');
select is((select created_at from public.data_sources where id = '93000000-0000-4000-8000-000000000001'),
    '2026-08-26'::timestamptz, 'source backfill uses the recorded connection time');
select is((select created_at from public.step_days where user_id = '92000000-0000-4000-8000-920000000001'),
    '2026-09-02'::timestamptz, 'daily creation backfill uses the last retained timestamp');
select is((select created_at from private.account_preferences where user_id = '92000000-0000-4000-8000-920000000001'),
    '2026-09-03'::timestamptz, 'preference backfill keeps its retained timestamp');
select ok((select created_at = last_success_at and updated_at = last_success_at
    from private.healthkit_step_syncs where user_id = '92000000-0000-4000-8000-920000000001'),
    'sync backfill uses the last recorded sync for both timestamps');
select ok((select created_at is not null and updated_at is not null
    from public.fight_members where fight_id = '94000000-0000-4000-8000-000000000001'),
    'rows without historical times receive initialization timestamps');
select is_empty($$
    select before.conrelid, before.conname from row_columns_test.before_keys before
    left join pg_constraint after on after.conrelid = before.conrelid and after.conname = before.conname
    where after.oid is null or pg_get_constraintdef(after.oid) <> before.definition
$$, 'migration retains every existing primary, unique, and foreign key');
select is((select count(*) from realtime.messages), (select total from row_columns_test.before_messages),
    'metadata backfill emits no Realtime messages');

create temporary table retained_rows (table_name text, unchanged boolean);
do $$
declare
    before record;
begin
    for before in select * from row_columns_test.before_rows loop
        execute format($query$
            insert into retained_rows select %L,
                (select count(*) from %s) = jsonb_array_length($1)
                and not exists (
                    select 1 from jsonb_array_elements($1) old_row
                    where not exists (select 1 from %s current_row where to_jsonb(current_row) @> old_row)
                )
        $query$, before.table_name, before.table_name, before.table_name) using before.rows;
    end loop;
end;
$$;
select ok(unchanged, table_name || ' retains every row and pre-existing value') from retained_rows order by table_name;
select * from finish();
rollback;
