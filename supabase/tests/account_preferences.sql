begin;
select plan(5);

select has_table('private', 'account_preferences', 'Account preferences remain private');
select ok(
    (select relrowsecurity from pg_class where oid = 'private.account_preferences'::regclass),
    'Account preferences have RLS'
);
select is(
    has_table_privilege('anon', 'private.account_preferences', 'SELECT,INSERT,UPDATE,DELETE'),
    false,
    'Anonymous clients cannot access account preferences'
);
select is(
    has_table_privilege('authenticated', 'private.account_preferences', 'SELECT,INSERT,UPDATE,DELETE'),
    false,
    'App clients cannot access account preferences directly'
);
select ok(
    has_table_privilege('postgres', 'private.account_preferences', 'SELECT,INSERT,UPDATE,DELETE'),
    'The authenticated backend can save account preferences'
);

select * from finish();
rollback;
