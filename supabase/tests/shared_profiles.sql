begin;
select plan(7);

select ok((select bool_and(relrowsecurity) from pg_class relation
    join pg_namespace schema on schema.oid = relation.relnamespace
    where schema.nspname = 'private' and relation.relname in ('profile_settings', 'profile_friendships',
        'profile_blocks', 'profile_reports', 'profile_events', 'profile_event_totals', 'profile_lookup_attempts',
        'rivalry_artworks', 'fight_record_contexts', 'fight_participation_records', 'fight_admin_actions')), 'new private tables enable RLS');
select ok(not has_table_privilege('authenticated', 'private.profile_settings', 'SELECT,INSERT,UPDATE,DELETE'), 'mobile cannot access sharing settings directly');
select ok(not has_table_privilege('authenticated', 'private.profile_friendships', 'SELECT,INSERT,UPDATE,DELETE'), 'mobile cannot forge accepted friendships');
select ok(not has_table_privilege('anon', 'private.profile_events', 'SELECT,INSERT,UPDATE,DELETE'), 'anonymous callers cannot read visitors');
select ok(not has_table_privilege('authenticated', 'private.rivalry_artworks', 'SELECT,INSERT,UPDATE,DELETE'), 'mobile cannot publish artwork or obtain object paths');
select ok(not has_table_privilege('authenticated', 'private.fight_participation_records', 'SELECT,INSERT,UPDATE,DELETE'), 'mobile cannot forge record evidence');
select ok(not has_function_privilege('authenticated', 'private.capture_profile_participation()', 'EXECUTE'), 'capture trigger is not an app RPC');

select * from finish();
rollback;
