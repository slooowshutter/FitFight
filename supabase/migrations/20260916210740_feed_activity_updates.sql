create table private.fight_membership_events (
    id uuid primary key default gen_random_uuid(),
    fight_id uuid not null references public.fights (id) on delete cascade,
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    state public.fight_member_state not null,
    occurred_at timestamptz
);

create index fight_membership_events_fight_time_idx
    on private.fight_membership_events (fight_id, occurred_at desc, id desc);
create index fight_membership_events_user_idx
    on private.fight_membership_events (user_id);

alter table private.fight_membership_events enable row level security;
alter table private.fight_membership_events force row level security;
revoke all on private.fight_membership_events from public, anon, authenticated;
grant all on private.fight_membership_events to postgres, service_role;

-- Earlier memberships only retained acceptance times, never invitation times.
insert into private.fight_membership_events (fight_id, user_id, state, occurred_at)
select fight_id, user_id, state, accepted_at
from public.fight_members
where state in ('accepted', 'deferred') and accepted_at is not null;

insert into private.fight_membership_events (fight_id, user_id, state, occurred_at)
select fight_id, invited_user_id, 'invited'::public.fight_member_state, null::timestamptz
from public.fight_invites
where invited_user_id is not null
group by fight_id, invited_user_id
union
select fight_id, user_id, 'invited'::public.fight_member_state, null::timestamptz
from public.fight_members where state = 'invited';

create function private.record_fight_membership_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'UPDATE' and new.state is not distinct from old.state then
        return null;
    end if;
    insert into private.fight_membership_events (fight_id, user_id, state, occurred_at)
    values (new.fight_id, new.user_id, new.state, statement_timestamp());
    return null;
end;
$$;

revoke all on function private.record_fight_membership_event() from public, anon, authenticated;
create trigger fight_members_record_activity
after insert or update on public.fight_members
for each row execute function private.record_fight_membership_event();

-- No content or identifiers cross the socket. Reads recheck membership and blocks.
create function private.broadcast_feed_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed jsonb;
    changed_post_id uuid;
    changed_fight_id uuid;
    changed_app_wide boolean := false;
    recipient uuid;
begin
    if tg_op = 'DELETE' then
        changed := to_jsonb(old);
    else
        changed := to_jsonb(new);
    end if;
    if tg_table_name = 'fight_posts' then
        changed_post_id := (changed->>'id')::uuid;
        changed_app_wide := (changed->>'app_wide')::boolean;
    else
        changed_post_id := (changed->>'post_id')::uuid;
        select p.app_wide into changed_app_wide
        from public.fight_posts p where p.id = changed_post_id;
    end if;
    changed_fight_id := (changed->>'fight_id')::uuid;

    for recipient in
        with affected_fights as (
            select changed_fight_id as id
            union
            select p.fight_id from public.fight_posts p where p.id = changed_post_id
            union
            select c.fight_id from public.fight_post_channels c where c.post_id = changed_post_id
        ), visible_fights as (
            select f.id from public.fights f
            where f.id in (select a.id from affected_fights a)
                or f.series_id in (
                    select original.series_id from public.fights original
                    where original.id in (select a.id from affected_fights a)
                )
        )
        select m.user_id from public.fight_members m
        where m.fight_id in (select v.id from visible_fights v)
            and m.state in ('accepted', 'deferred', 'invited')
        union
        select p.user_id from public.profiles p
        where changed_app_wide and p.deleted_at is null
        union
        select (changed->>'user_id')::uuid
        where tg_table_name = 'fight_membership_events'
        union
        select (changed->>'blocker_id')::uuid where tg_table_name = 'feed_blocks'
        union
        select (changed->>'blocked_id')::uuid where tg_table_name = 'feed_blocks'
    loop
        if recipient is not null then
            perform realtime.send('{}'::jsonb, 'feed_changed', 'fitfight:fights:' || recipient::text, true);
        end if;
    end loop;
    return null;
end;
$$;

revoke all on function private.broadcast_feed_changes() from public, anon, authenticated;

create trigger fight_posts_broadcast_feed
after insert or update or delete on public.fight_posts
for each row execute function private.broadcast_feed_changes();
create trigger fight_post_channels_broadcast_feed
after insert or update or delete on public.fight_post_channels
for each row execute function private.broadcast_feed_changes();
create trigger fight_post_comments_broadcast_feed
after insert or update or delete on public.fight_post_comments
for each row execute function private.broadcast_feed_changes();
create trigger fight_post_reactions_broadcast_feed
after insert or update or delete on public.fight_post_reactions
for each row execute function private.broadcast_feed_changes();
create trigger fight_membership_events_broadcast_feed
after insert on private.fight_membership_events
for each row execute function private.broadcast_feed_changes();
create trigger feed_blocks_broadcast_feed
after insert or delete on private.feed_blocks
for each row execute function private.broadcast_feed_changes();
