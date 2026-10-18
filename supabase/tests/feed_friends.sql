begin;
select plan(13);

select has_column(
    'public',
    'fight_posts',
    'to_friends',
    'to_friends sends a post to the author''s friends'
);

-- 1111 posts. 2222 is a friend, 3333 shares a fight, 4444 is a stranger.
insert into auth.users (id) values
    ('11111111-1111-4111-8111-111111111111'),
    ('22222222-2222-4222-8222-222222222222'),
    ('33333333-3333-4333-8333-333333333333'),
    ('44444444-4444-4444-8444-444444444444');

insert into private.profile_friendships (user_low, user_high, requester_id, state, accepted_at)
values (
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    'accepted',
    now()
);

insert into public.fights (
    id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
) values (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    '11111111-1111-4111-8111-111111111111',
    'Office',
    'live',
    now(),
    now() + interval '3 days',
    'UTC',
    'highest_total',
    'shared'
);

insert into public.fight_members (fight_id, user_id, state) values
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '11111111-1111-4111-8111-111111111111', 'accepted'),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '33333333-3333-4333-8333-333333333333', 'accepted');

insert into public.fight_posts (id, fight_id, author_id, body, audience, to_friends) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '11111111-1111-4111-8111-111111111111', 'Friends only', 'main', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', '11111111-1111-4111-8111-111111111111', 'Friends and Office', 'fight', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', null, '11111111-1111-4111-8111-111111111111', 'Old Main', 'main', false);

insert into public.fight_post_channels (post_id, fight_id) values
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');

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

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select ok(
    private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    'the author sees a friends-only post'
);

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select ok(
    private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    'a friend sees a friends-only post'
);
select ok(
    private.current_user_can_see_fight_post('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    'a friend outside the fight sees a friends and fight post'
);
select ok(
    not private.current_user_can_see_fight_post('dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
    'a friend does not gain old Main posts'
);

select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select ok(
    not private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    'a fight opponent who is not a friend cannot see a friends-only post'
);
select ok(
    private.current_user_can_see_fight_post('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    'a fight opponent still sees the post in their fight'
);
select ok(
    private.current_user_can_see_fight_post('dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
    'old Main posts keep their shared-fight rule'
);

select pg_temp.as_user('44444444-4444-4444-8444-444444444444');
select ok(
    not private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
        and not private.current_user_can_see_fight_post('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    'a stranger sees neither post'
);

insert into private.feed_blocks (blocker_id, blocked_id) values
    ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select ok(
    not private.current_user_can_see_fight_post('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    'a friend the author hid no longer sees friends posts'
);
delete from private.feed_blocks
where blocker_id = '11111111-1111-4111-8111-111111111111';

delete from public.fights where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select is(
    (
        select audience || ':' || coalesce(fight_id::text, 'none')
        from public.fight_posts
        where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    ),
    'main:none',
    'a friends post outlives its deleted fight as friends-only'
);
select ok(
    private.current_user_can_see_fight_post('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    'the friend still sees it'
);

select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select ok(
    not private.current_user_can_see_fight_post('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    'the former opponent who is not a friend does not'
);

select * from finish();
rollback;
