import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { profileMeasurementGroupSchema, profileMeasurementTotalsSchema } from "@/lib/types/profiles/profile-measurement";
import type { Sql, TransactionSql } from "postgres";
import { profileAccess } from "@/lib/domain/profiles/profile-access";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { profileCountRowSchema, profileFeatureConfigSchema, type ProfileViewRequest } from "@/lib/types/profiles/shared-profile";
import { loadProfileAccess } from "./shared-profiles-supabase-query";

/** Event IDs deduplicate transport replay; qualifying visits use a rolling window in one direction. */
export async function recordProfileView(viewerId: string, targetId: string, input: ProfileViewRequest, database: Sql = createDatabaseClient()) {
    if (viewerId === targetId || !profileFeatureConfigSchema.parse({ measurement: process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED }).measurement) {
        return { recorded: false };
    }
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, viewerId, targetId, true);
        if (!profileAccess(row.settings, row.relationship).shared) return { recorded: false };
        const prior = await sql`select event_id from private.profile_events where actor_id = ${viewerId} and event_id = ${input.event_id}`;
        if (prior.length > 0) return { recorded: false };
        const [count] = await sql`select count(*)::int n from private.profile_events where actor_id = ${viewerId}
            and kind = 'view' and created_at > now() - interval '1 hour'`;
        if (profileCountRowSchema.parse(count).n >= 60) throw new ApiError(429, "rate_limited", "Too many profile opens");
        await sql`
            insert into private.profile_events(actor_id, target_id, event_id, source, kind, qualifying)
            values (${viewerId}, ${targetId}, ${input.event_id}, ${input.source}, 'view', not exists (
                select 1 from private.profile_events where actor_id = ${viewerId} and target_id = ${targetId}
                    and kind = 'view' and qualifying and created_at > now() - interval '30 minutes'
            ))
        `;
        return { recorded: true };
    });
}

/** Scheduled independently of user activity, including accounts that stop opening the app. */
export async function pruneProfileEvents(database: Sql = createDatabaseClient()) {
    return database.begin(async (sql) => {
        const events = await sql`
            with expired as (
                delete from private.profile_events where created_at < now() - interval '30 days'
                returning kind, source, attributed_source, qualifying
            )
            insert into private.profile_event_totals(kind, source, events, qualifying)
            select kind, coalesce(source, attributed_source, ''), count(*), count(*) filter (where qualifying)
            from expired group by kind, coalesce(source, attributed_source, '')
            on conflict (kind, source) do update set events = private.profile_event_totals.events + excluded.events,
                qualifying = private.profile_event_totals.qualifying + excluded.qualifying
            returning kind
        `;
        const lookups = await sql`delete from private.profile_lookup_attempts where created_at < now() - interval '1 hour' returning id`;
        return { archived_groups: events.length, lookup_attempts_deleted: lookups.length };
    });
}

/** One conversion per directed pair/round, attributed to that actor's last visible open within seven days. */
export async function recordSharedFightParticipation(sql: TransactionSql, fightId: string, joiningUserId: string | null) {
    if (!profileFeatureConfigSchema.parse({ measurement: process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED }).measurement) return;
    await sql`
        insert into private.profile_events(actor_id, event_id, target_id, kind, fight_id, attributed_source)
        select mine.user_id, gen_random_uuid(), theirs.user_id, 'shared_fight', ${fightId}, (
            select source from private.profile_events where actor_id = mine.user_id and target_id = theirs.user_id
                and kind = 'view' and created_at > now() - interval '7 days' order by created_at desc limit 1
        )
        from public.fight_members mine
        join public.fight_members theirs on theirs.fight_id = mine.fight_id and theirs.user_id <> mine.user_id
        where mine.fight_id = ${fightId} and mine.state = 'accepted' and theirs.state = 'accepted'
            and (${joiningUserId}::uuid is null or mine.user_id = ${joiningUserId} or theirs.user_id = ${joiningUserId})
            and not exists (
                select 1 from (
                    select blocker_id, blocked_id from private.profile_blocks
                    union all select blocker_id, blocked_id from private.feed_blocks
                    union all select blocker_id, blocked_id from private.feedback_blocks
                ) blocks where (blocker_id = mine.user_id and blocked_id = theirs.user_id)
                    or (blocker_id = theirs.user_id and blocked_id = mine.user_id)
            )
        on conflict (actor_id, target_id, fight_id) where kind = 'shared_fight' do nothing
    `;
}

/** Operator-only totals contain no named visitors or health data. Raw events expire after thirty days. */
export async function readProfileMeasurements(userId: string, database: Sql = createDatabaseClient()) {
    if (!canAdministerFights(userId)) throw new ApiError(403, "forbidden", "Only Marc can read profile measurements");
    const rows = await database`
        select kind, coalesce(source, attributed_source) source, count(*)::int events,
            count(distinct actor_id)::int unique_actors, count(*) filter (where qualifying)::int qualifying
        from private.profile_events where created_at > now() - interval '30 days'
        group by kind, coalesce(source, attributed_source) order by kind, source
    `;
    const totals = await database`select kind, nullif(source, '') source, events::float8, qualifying::float8 from private.profile_event_totals order by kind, source`;
    return { days: 30, attribution_days: 7, groups: profileMeasurementGroupSchema.array().parse(rows),
        archived_groups: profileMeasurementTotalsSchema.array().parse(totals) };
}
