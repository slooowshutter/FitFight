begin;
select plan(5);

select has_column(
    'public',
    'fight_posts',
    'app_wide',
    'app_wide marks a post for every signed-in Feed'
);

insert into auth.users (id) values
    ('11111111-1111-4111-8111-111111111111'),
    ('22222222-2222-4222-8222-222222222222');

insert into public.fights (
    id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
) values (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    '11111111-1111-4111-8111-111111111111',
    'Shape',
    'live',
    now(),
    now() + interval '3 days',
    'UTC',
    'highest_total',
    'shared'
);

insert into public.fight_posts (
    id, fight_id, author_id, body, audience, broadcast, app_wide
) values
    (
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        null,
        '11111111-1111-4111-8111-111111111111',
        'Hello everyone',
        'main',
        true,
        true
    ),
    (
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        null,
        '11111111-1111-4111-8111-111111111111',
        'Circle only',
        'main',
        true,
        false
    );

select throws_ok(
    $$
        insert into public.fight_posts (
            fight_id, author_id, body, audience, broadcast, app_wide
        ) values (
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            '11111111-1111-4111-8111-111111111111',
            'No',
            'fight',
            false,
            true
        )
    $$,
    '23514',
    null,
    'app_wide posts stay on Main with no fight'
);

select ok(
    private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    'any signed-in user can see an app-wide post'
);

create function pg_temp.as_user(uid uuid)
returns void
language plpgsql
as $$
begin
    perform set_config(
        'request.jwt.claims',
        json_build_object('sub', uid::text, 'role', 'authenticated')::text,
        true
    );
    perform set_config('request.jwt.claim.sub', uid::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select is(
    (
        select count(*)::int
        from public.fight_posts
        where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    1,
    'a stranger can read an app-wide post'
);

select is(
    (
        select count(*)::int
        from public.fight_posts
        where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    ),
    0,
    'a stranger cannot read a circle Main post'
);

select * from finish();
rollback;
