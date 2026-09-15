begin;
select plan(8);

select has_table('public', 'fight_post_channels', 'posts can belong to several fights');
select has_column('public', 'fight_posts', 'broadcast', 'broadcast marks a post to every fight the author chose');
select has_column('public', 'fight_series', 'suggested', 'Marc can flag a series for New');
select is(
    has_table_privilege('authenticated', 'public.fight_post_channels', 'INSERT'),
    false,
    'clients cannot insert post channels'
);
select ok(
    to_regprocedure('private.rehome_fight_posts_before_fight_delete()') is not null,
    'deleting a fight rehomes shared posts'
);

insert into auth.users (id) values ('11111111-1111-4111-8111-111111111111');

insert into public.fights (
    id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
) values
    (
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        '11111111-1111-4111-8111-111111111111',
        'Primary',
        'live',
        now(),
        now() + interval '3 days',
        'UTC',
        'highest_total',
        'shared'
    ),
    (
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        '11111111-1111-4111-8111-111111111111',
        'Other',
        'live',
        now(),
        now() + interval '3 days',
        'UTC',
        'highest_total',
        'shared'
    ),
    (
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        '11111111-1111-4111-8111-111111111111',
        'Public primary',
        'live',
        now(),
        now() + interval '3 days',
        'UTC',
        'highest_total',
        'shared'
    ),
    (
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        '11111111-1111-4111-8111-111111111111',
        'Solo',
        'live',
        now(),
        now() + interval '3 days',
        'UTC',
        'highest_total',
        'shared'
    );

insert into public.fight_posts (id, fight_id, author_id, body, audience, broadcast)
values
    (
        '11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        '11111111-1111-4111-8111-111111111111',
        'Shared',
        'fight',
        false
    ),
    (
        '22222222-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        '11111111-1111-4111-8111-111111111111',
        'Public',
        'fight',
        true
    ),
    (
        '33333333-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        '11111111-1111-4111-8111-111111111111',
        'Solo',
        'fight',
        false
    );

insert into public.fight_post_channels (post_id, fight_id)
values
    ('11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    ('11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    ('22222222-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
    ('33333333-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');

delete from public.fights where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
    (
        select fight_id
        from public.fight_posts
        where id = '11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
    'shared post stays on the remaining fight'
);

delete from public.fights where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select is(
    (
        select audience
        from public.fight_posts
        where id = '22222222-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    'main',
    'a Public post stays on Main when its last fight goes away'
);

delete from public.fights where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

select is(
    (
        select count(*)::int
        from public.fight_posts
        where id = '33333333-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    0,
    'a post only on the deleted fight is removed'
);

select * from finish();
rollback;
