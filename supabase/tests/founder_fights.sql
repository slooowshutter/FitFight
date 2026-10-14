begin;
select plan(8);

-- Host (founder), challenger, and a friend who shares an ordinary fight with the host.
insert into auth.users (id) values
    ('a1000000-0000-4000-8000-000000000001'),
    ('a1000000-0000-4000-8000-000000000002'),
    ('a1000000-0000-4000-8000-000000000003');

insert into public.fights (
    id, owner_id, host_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
) values
    ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000001', 'Fight Marc', 'live', now(), now() + interval '30 days',
        'GMT', 'highest_total', 'shared'),
    ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000003',
        null, 'Ordinary', 'live', now(), now() + interval '7 days', 'UTC', 'highest_total', 'shared');

insert into public.fight_members (fight_id, user_id, state) values
    ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'accepted'),
    ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'accepted'),
    ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'accepted'),
    ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000003', 'accepted');

create function pg_temp.pings(uid uuid)
returns bigint
language sql
as $$
    select count(*) from realtime.messages where topic = 'fitfight:fights:' || uid::text;
$$;

create temporary table before_pings as select
    pg_temp.pings('a1000000-0000-4000-8000-000000000001') as host,
    pg_temp.pings('a1000000-0000-4000-8000-000000000002') as challenger;
update public.fight_members set current_value = 1000
where fight_id = 'a2000000-0000-4000-8000-000000000001';

select ok(
    pg_temp.pings('a1000000-0000-4000-8000-000000000002') > (select challenger from before_pings),
    'a founder round change pings the challenger'
);
select is(
    pg_temp.pings('a1000000-0000-4000-8000-000000000001'), (select host from before_pings),
    'a founder round change never pings its host'
);

update public.fight_members set current_value = 2000
where fight_id = 'a2000000-0000-4000-8000-000000000002';
select ok(
    pg_temp.pings('a1000000-0000-4000-8000-000000000001') > (select host from before_pings),
    'the host is still pinged for an ordinary fight'
);

create temporary table before_feed as select
    pg_temp.pings('a1000000-0000-4000-8000-000000000001') as host,
    pg_temp.pings('a1000000-0000-4000-8000-000000000002') as challenger;
insert into public.fight_posts (id, fight_id, author_id, body, audience, broadcast) values
    ('a3000000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000002', 'Inside the founder round', 'fight', false);
select ok(
    pg_temp.pings('a1000000-0000-4000-8000-000000000002') > (select challenger from before_feed),
    'a founder round post pings the challenger''s Feed'
);
select is(
    pg_temp.pings('a1000000-0000-4000-8000-000000000001'), (select host from before_feed),
    'a founder round post never pings its host''s Feed'
);

insert into public.fight_posts (id, fight_id, author_id, body, audience, broadcast) values
    ('a3000000-0000-4000-8000-000000000001', null, 'a1000000-0000-4000-8000-000000000001', 'Host on Main', 'main', true),
    ('a3000000-0000-4000-8000-000000000002', null, 'a1000000-0000-4000-8000-000000000002', 'Challenger on Main', 'main', true);

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
end;
$$;

select pg_temp.as_user('a1000000-0000-4000-8000-000000000002');
select ok(
    not private.current_user_can_see_fight_post('a3000000-0000-4000-8000-000000000001'),
    'a founder round does not show the host''s Main posts to the challenger'
);

select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
select ok(
    not private.current_user_can_see_fight_post('a3000000-0000-4000-8000-000000000002'),
    'a founder round does not show the challenger''s Main posts to the host'
);

select pg_temp.as_user('a1000000-0000-4000-8000-000000000003');
select ok(
    private.current_user_can_see_fight_post('a3000000-0000-4000-8000-000000000001'),
    'an ordinary shared fight still shows the host''s Main posts'
);

select * from finish();
rollback;
