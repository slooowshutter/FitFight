begin;
select plan(7);

select ok(
    (
        select bool_and(has_table_privilege(
            'service_role',
            format('%I.%I', namespace.nspname, relation.relname),
            'SELECT,INSERT,UPDATE,DELETE'
        ))
        from pg_class as relation
        join pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
            and relation.relkind = 'r'
    ),
    'service_role can read and write every public table'
);

select ok(
    (
        select bool_and(not has_table_privilege(
            'anon',
            format('%I.%I', namespace.nspname, relation.relname),
            'SELECT,INSERT,UPDATE,DELETE'
        ))
        from pg_class as relation
        join pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
            and relation.relkind = 'r'
    ),
    'anon has no Data API writes or reads on public tables'
);

select ok(
    has_table_privilege('authenticated', 'public.profiles', 'SELECT')
        and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE')
        and has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE')
        and not has_column_privilege('authenticated', 'public.profiles', 'user_id', 'UPDATE')
        and has_column_privilege('authenticated', 'public.fights', 'owner_id', 'INSERT')
        and not has_column_privilege('authenticated', 'public.fights', 'state', 'UPDATE')
        and has_column_privilege('authenticated', 'public.fight_members', 'state', 'UPDATE')
        and not has_column_privilege('authenticated', 'public.fight_members', 'current_value', 'UPDATE')
        and has_column_privilege('authenticated', 'public.fight_invites', 'id', 'SELECT')
        and not has_column_privilege('authenticated', 'public.fight_invites', 'token_hash', 'SELECT'),
    'authenticated keeps the legacy column grants and not the hidden columns'
);

select ok(
    has_table_privilege('authenticated', 'public.step_days', 'SELECT')
        and not has_table_privilege('authenticated', 'public.step_days', 'INSERT')
        and has_table_privilege('authenticated', 'public.metric_days', 'SELECT')
        and not has_table_privilege('authenticated', 'public.metric_days', 'INSERT')
        and has_table_privilege('authenticated', 'public.fight_series', 'SELECT')
        and has_table_privilege('authenticated', 'public.feedback_posts', 'SELECT')
        and not has_table_privilege('authenticated', 'public.feedback_votes', 'SELECT'),
    'authenticated can read the shared tables its policies allow'
);

select ok(
    not has_table_privilege('anon', 'private.whoop_connections', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('authenticated', 'private.whoop_connections', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('service_role', 'private.whoop_connections', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('service_role', 'private.snake_scores', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('service_role', 'private.fight_group_images', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('service_role', 'private.alert_responses', 'SELECT,INSERT,UPDATE,DELETE')
        and not has_table_privilege('service_role', 'private.app_error_logs', 'SELECT,INSERT,UPDATE,DELETE')
        and has_table_privilege('postgres', 'private.whoop_connections', 'SELECT,INSERT')
        and has_table_privilege('postgres', 'private.snake_scores', 'SELECT,INSERT')
        and has_table_privilege('postgres', 'private.alert_responses', 'SELECT,INSERT'),
    'private server tables stay closed to Data API roles'
);

select ok(
    has_sequence_privilege('postgres', 'private.fight_admin_actions_id_seq', 'USAGE,SELECT')
        and has_sequence_privilege('service_role', 'private.fight_admin_actions_id_seq', 'USAGE,SELECT')
        and has_sequence_privilege('postgres', 'private.profile_lookup_attempts_id_seq', 'USAGE,SELECT')
        and has_sequence_privilege('service_role', 'private.profile_lookup_attempts_id_seq', 'USAGE,SELECT'),
    'identity inserts can use their sequences'
);

select ok(
    not has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE')
        and not has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
    'the signup trigger is not an app RPC'
);

select * from finish();
rollback;
