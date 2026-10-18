-- Fights now rank a member without final Steps by their last synced total, and finalize early
-- once no missing final sync can change a rank (Marc, 15 Oct 2026).

-- The final-sync deadline is a per-fight setting the owner can change. It starts on for the
-- Everybody fight, Suggested fights and Fight Marc, and off for fights people make and friend
-- rounds, which wait for everyone's final Steps. Older backends ignore it and keep closing at 24h.
begin;

set local lock_timeout = '5s';

alter table public.fights
    add column closes_after_grace boolean not null default true;

comment on column public.fights.closes_after_grace is
    'On: finalize at ends_at + final_sync_grace_seconds even if final Steps are missing. Off: wait for everyone. Copied to every new round.';

-- The backfill changes a setting, not a result: no broadcasts, history or timestamps.
-- NOTE: only around this update. Replica mode also mutes PostgREST's schema reload on DDL.
set local session_replication_role = replica;

update public.fights as fight
set closes_after_grace = false
where fight.state in ('draft', 'inviting', 'scheduled', 'live', 'awaiting_final_sync')
    and fight.host_id is null
    and not exists (
        select 1 from public.fight_series as series
        where series.id = fight.series_id and (series.suggested or series.join_code = 'PGG7')
    );

set local session_replication_role = origin;

-- A first place no longer has to be complete, so new result summaries count every first place.
create or replace function private.snapshot_profile_result_evidence(target_fight_id uuid)
returns void language sql security definer set search_path = '' as $$
    update private.fight_record_contexts context
    set result_summary = (
        select jsonb_build_object(
            'field_size', count(*) filter (where entrant) + context.deleted_entrants,
            'complete_finishers', count(*) filter (where entrant and departure is null and complete),
            'first_place_finishers', count(*) filter (where entrant and departure is null and complete and rank = 1),
            'rank_one_finishers', count(*) filter (where entrant and departure is null and rank = 1),
            'verified', not context.unknown_deleted_participant
                and coalesce(bool_and(reliable or state in ('invited', 'declined', 'deferred')), true)
                and coalesce(bool_and(not entrant or departure is not null
                    or (finalized_at is not null and complete is not null and rank is not null)), true)
        )
        from (
            select member.*, member.entered_at is not null and member.entered_at < fight.ends_at
                and (member.departed_at is null or member.departed_at > fight.starts_at) entrant
            from private.fight_participation_records member
            join public.fights fight on fight.id = member.fight_id
            where member.fight_id = target_fight_id
        ) evidence
    )
    where context.fight_id = target_fight_id and context.result_summary is null;
$$;

-- PostgREST updates fights.closes_after_grace from Edit fight.
notify pgrst, 'reload schema';

commit;
