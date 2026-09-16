-- New sharing permissions never trust legacy public.friendships writes.
-- Historical day zones are unknown; only future uploads can supply them accurately.
alter table public.metric_days add column time_zone text;

create table private.profile_settings (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    competitive boolean not null default false,
    audience text not null default 'private' check (audience in ('private', 'public')),
    activity_audience text not null default 'off' check (activity_audience in ('off', 'friends', 'opponents', 'public')),
    activity_days integer not null default 7 check (activity_days in (7, 30)),
    artwork_allowed boolean not null default false,
    revision integer not null default 0 check (revision >= 0),
    updated_at timestamptz not null default now(),
    check (activity_audience <> 'public' or audience = 'public')
);

create table private.profile_friendships (
    user_low uuid not null references public.profiles(user_id) on delete cascade,
    user_high uuid not null references public.profiles(user_id) on delete cascade,
    requester_id uuid not null references public.profiles(user_id) on delete cascade,
    state text not null default 'pending' check (state in ('pending', 'accepted')),
    created_at timestamptz not null default now(),
    accepted_at timestamptz,
    primary key (user_low, user_high),
    check (user_low < user_high),
    check (requester_id in (user_low, user_high)),
    check ((state = 'accepted') = (accepted_at is not null))
);
create index profile_friendships_high_idx on private.profile_friendships(user_high, user_low);

create table private.profile_blocks (
    blocker_id uuid not null references public.profiles(user_id) on delete cascade,
    blocked_id uuid not null references public.profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);
create index profile_blocks_target_idx on private.profile_blocks(blocked_id, blocker_id);

create table private.profile_reports (
    reporter_id uuid not null references public.profiles(user_id) on delete cascade,
    target_id uuid not null references public.profiles(user_id) on delete cascade,
    reason text not null check (length(reason) between 1 and 1000),
    created_at timestamptz not null default now(),
    primary key (reporter_id, target_id),
    check (reporter_id <> target_id)
);
create index profile_reports_target_idx on private.profile_reports(target_id);

create table private.fight_admin_actions (
    id bigint generated always as identity primary key,
    actor_id uuid not null references public.profiles(user_id) on delete cascade,
    fight_id uuid not null references public.fights(id) on delete cascade,
    changes jsonb not null,
    created_at timestamptz not null default now()
);
create index fight_admin_actions_actor_idx on private.fight_admin_actions(actor_id);
create index fight_admin_actions_fight_idx on private.fight_admin_actions(fight_id);

create table private.profile_events (
    actor_id uuid not null references public.profiles(user_id) on delete cascade,
    event_id uuid not null,
    target_id uuid not null references public.profiles(user_id) on delete cascade,
    fight_id uuid references public.fights(id) on delete cascade,
    kind text not null check (kind in ('view', 'friend_request', 'friend_accept', 'shared_fight')),
    source text check (source in ('standings', 'participants', 'feed', 'comments', 'reactions', 'feedback', 'friends', 'lookup')),
    qualifying boolean not null default false,
    attributed_source text check (attributed_source in ('standings', 'participants', 'feed', 'comments', 'reactions', 'feedback', 'friends', 'lookup')),
    created_at timestamptz not null default now(),
    primary key (actor_id, event_id),
    check (actor_id <> target_id)
);
create index profile_events_pair_time_idx on private.profile_events(actor_id, target_id, created_at desc);
create unique index profile_events_shared_fight_idx on private.profile_events(actor_id, target_id, fight_id) where kind = 'shared_fight';
create index profile_events_fight_idx on private.profile_events(fight_id);
create index profile_events_retention_idx on private.profile_events(created_at);
create index profile_events_target_idx on private.profile_events(target_id);

create table private.profile_lookup_attempts (
    id bigint generated always as identity primary key,
    actor_id uuid not null references public.profiles(user_id) on delete cascade,
    created_at timestamptz not null default now()
);
create index profile_lookup_attempts_actor_idx on private.profile_lookup_attempts(actor_id, created_at desc);

create table private.rivalry_artworks (
    id uuid primary key default gen_random_uuid(),
    user_low uuid not null references public.profiles(user_id) on delete cascade,
    user_high uuid not null references public.profiles(user_id) on delete cascade,
    artwork_version integer not null default 1,
    state text not null default 'queued' check (state in ('queued', 'generating', 'ready', 'failed', 'needs_review', 'cancelled')),
    hidden boolean not null default false,
    low_revision integer not null,
    high_revision integer not null,
    provider_request_id text,
    object_path text unique,
    claimed_at timestamptz,
    created_at timestamptz not null default now(),
    unique (user_low, user_high, artwork_version),
    check (user_low < user_high),
    check (state <> 'ready' or object_path is not null)
);
create index rivalry_artworks_high_idx on private.rivalry_artworks(user_high, user_low);
create index rivalry_artworks_work_idx on private.rivalry_artworks(created_at) where state = 'queued';

-- These tables capture participation facts, never calculate wins or change scoring.
create table private.fight_record_contexts (
    fight_id uuid primary key references public.fights(id) on delete cascade,
    category text not null check (category in ('public', 'private', 'unknown')),
    captured_at timestamptz not null default now()
);
create table private.fight_participation_records (
    fight_id uuid not null references public.fights(id) on delete cascade,
    user_id uuid not null references public.profiles(user_id) on delete cascade,
    entered_at timestamptz,
    departed_at timestamptz,
    departure text check (departure in ('voluntary', 'removed', 'unknown')),
    state text not null,
    rank integer,
    final_value numeric,
    complete boolean,
    finalized_at timestamptz,
    reliable boolean not null,
    primary key (fight_id, user_id)
);
create index fight_participation_user_idx on private.fight_participation_records(user_id, fight_id);

insert into private.fight_record_contexts(fight_id, category)
select fight.id, case when fight.starts_at > now() then
    case when series.visibility = 'joinable' then 'public' else 'private' end
    else 'unknown' end
from public.fights fight left join public.fight_series series on series.id = fight.series_id;

insert into private.fight_participation_records
    (fight_id, user_id, entered_at, state, rank, final_value, complete, finalized_at, reliable)
select member.fight_id, member.user_id,
    case when member.state = 'accepted' or member.finalized_at is not null then member.accepted_at end,
    member.state, member.rank, member.final_value, member.final_steps_complete, member.finalized_at,
    (member.finalized_at is not null and member.accepted_at is not null)
        or member.state in ('invited', 'declined', 'deferred')
from public.fight_members member;

create function private.capture_fight_record_context()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    insert into private.fight_record_contexts(fight_id, category)
    select new.id, case when series.visibility = 'joinable' then 'public' else 'private' end
    from (select 1) singleton
    left join public.fight_series series on series.id = new.series_id
    on conflict (fight_id) do nothing;
    if tg_op = 'UPDATE' then
        if old.series_id is null and new.series_id is not null then
            update private.fight_record_contexts context
            set category = case when series.visibility = 'joinable' then 'public' else 'private' end
            from public.fight_series series where series.id = new.series_id and context.fight_id = new.id;
        end if;
    end if;
    return new;
end;
$$;
create trigger capture_fight_record_context after insert or update of series_id on public.fights
    for each row execute function private.capture_fight_record_context();

create function private.capture_profile_participation()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    cause text;
begin
    if tg_op = 'UPDATE' then
        if old.state = new.state and old.finalized_at is not distinct from new.finalized_at then
            return new;
        end if;
    end if;
    cause := case when current_setting('role', true) in ('none', 'postgres', 'service_role')
        then nullif(current_setting('fitfight.membership_departure', true), '') end;
    if cause is null or cause not in ('voluntary', 'removed') then cause := 'unknown'; end if;
    insert into private.fight_participation_records
        (fight_id, user_id, entered_at, departed_at, departure, state, rank, final_value, complete, finalized_at, reliable)
    values (new.fight_id, new.user_id,
        case when new.state = 'accepted' then clock_timestamp() end,
        case when new.state = 'withdrawn' then clock_timestamp() end,
        case when new.state = 'withdrawn' then cause end,
        new.state, new.rank, new.final_value, new.final_steps_complete, new.finalized_at,
        new.state <> 'withdrawn' or cause <> 'unknown')
    on conflict (fight_id, user_id) do update set
        entered_at = coalesce(private.fight_participation_records.entered_at, excluded.entered_at),
        departed_at = case when excluded.state = 'accepted' then null when excluded.state = 'withdrawn' then excluded.departed_at
            else private.fight_participation_records.departed_at end,
        departure = case when excluded.state = 'accepted' then null when excluded.state = 'withdrawn' then excluded.departure
            else private.fight_participation_records.departure end,
        state = excluded.state, rank = excluded.rank, final_value = excluded.final_value,
        complete = excluded.complete, finalized_at = excluded.finalized_at,
        reliable = private.fight_participation_records.reliable and excluded.reliable
    where private.fight_participation_records.finalized_at is null;
    return new;
end;
$$;
create trigger capture_profile_participation after insert or update on public.fight_members
    for each row execute function private.capture_profile_participation();

-- Old clients can still edit visibility. Clear suggestions instead of rejecting their edit.
create function private.preserve_profile_fight_category()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.visibility <> 'joinable' or new.paused_at is not null then
        new.suggested := false;
        new.suggested_at := null;
    end if;
    if new.visibility is distinct from old.visibility then
        update private.fight_record_contexts context
        set category = case when new.visibility = 'joinable' then 'public' else 'private' end
        from public.fights fight
        where fight.id = context.fight_id and fight.series_id = new.id
            and fight.starts_at > clock_timestamp();
    end if;
    return new;
end;
$$;
create trigger preserve_profile_fight_category before update on public.fight_series
    for each row execute function private.preserve_profile_fight_category();

do $$
declare table_name text;
begin
    foreach table_name in array array['profile_settings', 'profile_friendships', 'profile_blocks',
        'profile_reports', 'profile_events', 'profile_lookup_attempts', 'rivalry_artworks',
        'fight_record_contexts', 'fight_participation_records', 'fight_admin_actions']
    loop
        execute format('alter table private.%I enable row level security', table_name);
        execute format('revoke all on private.%I from public, anon, authenticated', table_name);
        execute format('grant all on private.%I to service_role', table_name);
    end loop;
end;
$$;
revoke all on function private.capture_fight_record_context(), private.capture_profile_participation(),
    private.preserve_profile_fight_category() from public, anon, authenticated;
