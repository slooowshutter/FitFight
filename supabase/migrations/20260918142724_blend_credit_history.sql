create table private.ai_credit_balances (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    available integer not null default 0 check (available >= 0),
    reserved integer not null default 0 check (reserved >= 0),
    sequence integer not null default 0 check (sequence >= 0),
    updated_at timestamptz not null default clock_timestamp()
);

create table private.ai_balance_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(user_id) on delete cascade,
    sequence integer not null check (sequence > 0),
    created_at timestamptz not null default clock_timestamp(),
    kind text not null check (kind in ('grant', 'reserve', 'consume', 'release', 'adjustment')),
    reason text not null check (reason ~ '^[a-z][a-z0-9_]{0,79}$'),
    actor text not null check (actor ~ '^(server:[a-z_]+|operator:[0-9a-f-]{36})$'),
    operation_key text not null unique check (length(operation_key) between 1 and 200),
    -- Request identifiers survive ordinary request pruning; account deletion still cascades.
    request_id uuid,
    action_key uuid,
    compensates_event_id uuid,
    quantity integer not null check (quantity > 0),
    available_before integer not null check (available_before >= 0),
    available_change integer not null,
    available_after integer not null check (available_after >= 0),
    reserved_before integer not null check (reserved_before >= 0),
    reserved_change integer not null,
    reserved_after integer not null check (reserved_after >= 0),
    unique (user_id, sequence),
    unique (user_id, id),
    foreign key (user_id, compensates_event_id) references private.ai_balance_events(user_id, id)
        deferrable initially deferred,
    check (available_before::bigint + available_change = available_after),
    check (reserved_before::bigint + reserved_change = reserved_after),
    check ((kind in ('reserve', 'consume', 'release')) = (request_id is not null)),
    check ((kind = 'reserve') = (action_key is not null)),
    check ((kind = 'adjustment') = (compensates_event_id is not null)),
    check (
        (kind = 'grant' and available_change = quantity and reserved_change = 0)
        or (kind = 'reserve' and available_change = -quantity and reserved_change = quantity)
        or (kind = 'consume' and available_change = 0 and reserved_change = -quantity)
        or (kind = 'release' and available_change = quantity and reserved_change = -quantity)
        or (kind = 'adjustment' and abs(available_change::bigint) = quantity and reserved_change = 0)
    )
);
create unique index ai_balance_events_action on private.ai_balance_events(user_id, action_key)
    where action_key is not null;
create unique index ai_balance_events_reservation on private.ai_balance_events(request_id)
    where kind = 'reserve';
create unique index ai_balance_events_settlement on private.ai_balance_events(request_id)
    where kind in ('consume', 'release');

-- These triggers enforce ledger integrity only. Admission and settlement policy remain in TypeScript.
create function private.guard_ai_balance_history() returns trigger
language plpgsql set search_path = '' as $$
begin
    if tg_op = 'DELETE' and not exists (
        select 1 from public.profiles where user_id = old.user_id
    ) then
        return old;
    end if;
    raise exception 'AI balance history is immutable; use a compensating event' using errcode = '23514';
end;
$$;
create trigger ai_balance_events_immutable before update or delete on private.ai_balance_events
    for each row execute function private.guard_ai_balance_history();
create trigger ai_credit_balances_no_delete before delete on private.ai_credit_balances
    for each row execute function private.guard_ai_balance_history();

create function private.check_ai_balance_chain() returns trigger
language plpgsql set search_path = '' as $$
declare
    balance private.ai_credit_balances;
    last_event private.ai_balance_events;
    previous_event private.ai_balance_events;
begin
    select * into balance from private.ai_credit_balances where user_id = new.user_id for update;
    if not found then
        if exists (select 1 from public.profiles where user_id = new.user_id) then
            raise exception 'Missing AI balance' using errcode = '23514';
        end if;
        return null;
    end if;
    if tg_table_name = 'ai_balance_events' then
        if new.sequence = 1 then
            if new.available_before <> 0 or new.reserved_before <> 0 then
                raise exception 'AI balance must begin at zero' using errcode = '23514';
            end if;
        else
            select * into previous_event from private.ai_balance_events
                where user_id = new.user_id and sequence = new.sequence - 1;
            if not found or previous_event.available_after <> new.available_before
                or previous_event.reserved_after <> new.reserved_before then
                raise exception 'Broken AI balance chain' using errcode = '23514';
            end if;
        end if;
    end if;
    select * into last_event from private.ai_balance_events
        where user_id = new.user_id order by sequence desc limit 1;
    if not found then
        if balance.sequence <> 0 or balance.available <> 0 or balance.reserved <> 0 then
            raise exception 'AI balance without event' using errcode = '23514';
        end if;
    elsif balance.sequence <> last_event.sequence or balance.available <> last_event.available_after
        or balance.reserved <> last_event.reserved_after then
        raise exception 'AI balance disagrees with history' using errcode = '23514';
    end if;
    return null;
end;
$$;
create constraint trigger ai_balance_chain after insert on private.ai_balance_events
    deferrable initially deferred for each row execute function private.check_ai_balance_chain();
create constraint trigger ai_balance_current after insert or update on private.ai_credit_balances
    deferrable initially deferred for each row execute function private.check_ai_balance_chain();

alter table private.ai_requests
    add column source_request_ids uuid[] not null default '{}',
    add column credit_price integer not null default 0 check (credit_price >= 0),
    add column credit_state text not null default 'none' check (credit_state in ('none', 'reserved', 'consumed', 'released')),
    add column admitted_at timestamptz,
    add column submission_attempted_at timestamptz,
    add column acknowledged_at timestamptz,
    add column provider_completed_at timestamptz,
    add column terminal_observed_at timestamptz,
    add column settled_at timestamptz,
    add column recovery_operation_key uuid,
    add column recovery_actor uuid,
    add column recovery_evidence text check (length(recovery_evidence) between 1 and 200),
    add constraint ai_request_credit_state check (
        (credit_price = 0 and credit_state = 'none') or
        (credit_price > 0 and (
            (credit_state = 'reserved' and status in ('starting', 'pending', 'running', 'start_unconfirmed') and settled_at is null) or
            (credit_state = 'consumed' and status = 'completed' and settled_at is not null) or
            (credit_state = 'released' and status in ('failed', 'cancelled') and settled_at is not null)
        ))
    );
create index ai_requests_reconciliation on private.ai_requests(next_poll_at)
    where status in ('pending', 'running');
create unique index ai_requests_blend_run on private.ai_requests ((run_handle ->> 'runId'))
    where run_handle is not null;

create table private.ai_http_logs (
    id uuid primary key,
    observed_at timestamptz not null,
    trace_id uuid not null,
    user_id uuid references public.profiles(user_id) on delete cascade,
    request_id uuid,
    leg text not null check (leg in ('app', 'blend', 'reconciler', 'operator')),
    operation text not null check (length(operation) between 1 and 40),
    workflow_id text check (length(workflow_id) <= 200),
    version_id text check (length(version_id) <= 200),
    run_id text check (length(run_id) <= 200),
    status integer check (status between 100 and 599),
    elapsed_ms integer not null check (elapsed_ms >= 0),
    disposition text check (disposition in ('submitted', 'recovered', 'observed', 'rejected')),
    outcome text check (length(outcome) <= 64),
    code text check (length(code) <= 80),
    upstream_code text check (length(upstream_code) <= 80)
);
create index ai_http_logs_retention on private.ai_http_logs(observed_at, id);
create index ai_http_logs_trace on private.ai_http_logs(trace_id);
create index ai_http_logs_request on private.ai_http_logs(request_id);

alter table private.ai_credit_balances enable row level security;
alter table private.ai_balance_events enable row level security;
alter table private.ai_http_logs enable row level security;
revoke all on private.ai_credit_balances, private.ai_balance_events, private.ai_http_logs
    from public, anon, authenticated, service_role, fitfight_backend_reader;
revoke all on function private.guard_ai_balance_history(), private.check_ai_balance_chain()
    from public, anon, authenticated, service_role, fitfight_backend_reader;
