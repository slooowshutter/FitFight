begin;
select plan(4);

select has_table('private', 'alert_responses', 'Alert responses remain private');
select ok(
    (select relrowsecurity from pg_class where oid = 'private.alert_responses'::regclass),
    'Alert responses have RLS'
);
select is(
    has_table_privilege('authenticated', 'private.alert_responses', 'SELECT,INSERT,UPDATE,DELETE'),
    false,
    'App clients cannot access alert responses directly'
);
select ok(
    has_table_privilege('postgres', 'private.alert_responses', 'SELECT,INSERT'),
    'The backend can record alert responses'
);

select * from finish();
rollback;
