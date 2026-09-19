begin;
select no_plan();

select is_empty($$
    select n.nspname, c.relname, required.name
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('id'), ('created_at'), ('updated_at')) required(name)
    left join pg_attribute a on a.attrelid = c.oid and a.attname = required.name
        and a.attnum > 0 and not a.attisdropped
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'p')
        and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
        and (a.attname is null or not a.attnotnull)
$$, 'every app table has non-null id, created_at, and updated_at');

select is_empty($$
    select n.nspname, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'id'
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'p')
        and not exists (
            select 1 from pg_index i where i.indrelid = c.oid
                and i.indisunique and i.indisvalid and i.indnkeyatts = 1
                and i.indkey[0] = a.attnum and i.indpred is null
        )
        and not exists (
            select 1 from pg_attrdef generated
            join pg_attribute source on source.attrelid = c.oid and source.attnotnull
                and pg_get_expr(generated.adbin, generated.adrelid) = quote_ident(source.attname)
            join pg_index i on i.indrelid = c.oid and i.indkey[0] = source.attnum
            where generated.adrelid = c.oid and generated.adnum = a.attnum and a.attgenerated = 's'
                and i.indisunique and i.indisvalid and i.indnkeyatts = 1 and i.indpred is null
        )
$$, 'each row ID is unique directly or through its generated source key');

select is_empty($$
    select table_schema, table_name, column_name
    from information_schema.columns
    where table_schema in ('public', 'private')
        and column_name in ('created_at', 'updated_at')
        and (data_type <> 'timestamp with time zone' or column_default is null)
$$, 'row timestamps retain timezone information and default on inserts');

select is_empty($$
    select n.nspname, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'p')
        and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
        and not exists (
            select 1 from pg_trigger t where t.tgrelid = c.oid
                and t.tgname = 'maintain_row_timestamps' and t.tgenabled = 'O'
        )
$$, 'every app table automatically maintains updated_at');

select ok(not has_function_privilege('authenticated', 'private.maintain_row_timestamps()', 'EXECUTE'),
    'timestamp maintenance is not an app-facing RPC');

insert into auth.users (id) values ('91000000-0000-4000-8000-000000000001');
select is((select id from public.profiles where user_id = '91000000-0000-4000-8000-000000000001'),
    '91000000-0000-4000-8000-000000000001'::uuid, 'legacy signup creates the same canonical profile ID');
select throws_ok($$
    update public.profiles set id = '91000000-0000-4000-8000-000000000002'
    where user_id = '91000000-0000-4000-8000-000000000001'
$$, '428C9', null, 'canonical and legacy profile identifiers cannot diverge');

insert into public.step_days (user_id, day, steps, created_at, updated_at)
values ('91000000-0000-4000-8000-000000000001', '2026-09-18', 10, '2026-09-01', '2026-09-02');
create temporary table original_day as select id, created_at from public.step_days
where user_id = '91000000-0000-4000-8000-000000000001';
insert into public.step_days (user_id, day, steps)
values ('91000000-0000-4000-8000-000000000001', '2026-09-18', 20)
on conflict (user_id, day) do update set steps = excluded.steps;
select is((select count(*)::int from public.step_days where user_id = '91000000-0000-4000-8000-000000000001'),
    1, 'legacy compound-key upserts still target exactly one row');
select results_eq($$
    select id, created_at from public.step_days where user_id = '91000000-0000-4000-8000-000000000001'
$$, 'select id, created_at from original_day', 'upserts preserve the row ID and creation time');
select ok((select updated_at > '2026-09-02'::timestamptz from public.step_days
    where user_id = '91000000-0000-4000-8000-000000000001'), 'omitted updated_at advances automatically');
update public.step_days set steps = 30, updated_at = '2026-09-03'
where user_id = '91000000-0000-4000-8000-000000000001';
select is((select updated_at from public.step_days where user_id = '91000000-0000-4000-8000-000000000001'),
    '2026-09-03'::timestamptz, 'explicit timestamps from existing writers retain their meaning');
select throws_ok($$
    insert into public.step_days (user_id, day, steps)
    values ('91000000-0000-4000-8000-000000000001', '2026-09-18', 40)
$$, '23505', null, 'a surrogate ID does not permit duplicate user/day records');

insert into private.account_preferences (user_id, language, updated_at)
values ('91000000-0000-4000-8000-000000000001', 'en', '2026-09-01');
update private.account_preferences set appearance = 'dark'
where user_id = '91000000-0000-4000-8000-000000000001';
select ok((select id = user_id and updated_at > '2026-09-01'::timestamptz
    from private.account_preferences where user_id = '91000000-0000-4000-8000-000000000001'),
    'private one-per-user rows keep their identity and maintain timestamps');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'created_at', 'UPDATE'),
    'legacy profile writers gain no timestamp-write permission');
select ok(not has_table_privilege('authenticated', 'private.account_preferences', 'SELECT'),
    'standard columns do not expose private rows');

insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
values ('95000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001',
    'Timestamp-only update', 'live', now(), now() + interval '1 day', 'UTC', 'highest_total', 'shared');
insert into public.fight_members (fight_id, user_id, state)
values ('95000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'accepted');
create temporary table original_messages as select count(*) total from realtime.messages;
update public.fight_members set state = state where fight_id = '95000000-0000-4000-8000-000000000001';
select is((select count(*) from realtime.messages), (select total from original_messages),
    'timestamp-only membership updates do not emit Fight or Feed invalidations');

select * from finish();
rollback;
