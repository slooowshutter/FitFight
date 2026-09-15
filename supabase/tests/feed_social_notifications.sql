begin;
select plan(10);

select has_table('private', 'notification_preferences', 'Notification preferences are private');

select ok(
    (select relrowsecurity from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'private' and c.relname = 'notification_preferences'),
    'Notification preferences have RLS'
);

select is(
    has_table_privilege('anon', 'private.notification_preferences', 'SELECT,INSERT,UPDATE,DELETE'),
    false,
    'Anonymous clients cannot access notification preferences'
);
select is(
    has_table_privilege('authenticated', 'private.notification_preferences', 'SELECT,INSERT,UPDATE,DELETE'),
    false,
    'App clients cannot access notification preferences directly'
);
select ok(
    has_table_privilege('service_role', 'private.notification_preferences', 'INSERT'),
    'The backend can record notification preferences'
);

select ok(
    exists (
        select 1
        from pg_constraint
        where conrelid = 'private.notification_intents'::regclass
            and conname = 'notification_intents_kind'
            and pg_get_constraintdef(oid) like '%feed_post%'
            and pg_get_constraintdef(oid) like '%post_comment%'
            and pg_get_constraintdef(oid) like '%comment_reply%'
            and pg_get_constraintdef(oid) like '%post_reaction%'
    ),
    'Social notification kinds are allowed on the outbox'
);

select ok(
    exists (
        select 1
        from pg_constraint
        where conrelid = 'private.notification_intents'::regclass
            and conname = 'notification_intents_slot'
            and pg_get_constraintdef(oid) like '%event%'
    ),
    'Immediate social notifications use the event slot'
);

select ok(
    exists (
        select 1
        from pg_constraint
        where conrelid = 'private.notification_intents'::regclass
            and conname = 'notification_intents_social_alert_body'
    ),
    'Social notification intents require an alert body'
);

select has_column('private', 'notification_preferences', 'feed_post', 'Feed post toggle exists');
select has_column('private', 'notification_preferences', 'comment_reply', 'Comment reply toggle exists');

select * from finish();
rollback;
