import type { Sql, TransactionSql } from "postgres";
import { profileAccess } from "@/lib/domain/profiles/profile-access";
import { classifyFightResult, profileRecord, rivalryRecord } from "@/lib/domain/profiles/profile-results";
import { profileStepStatistics } from "@/lib/domain/profiles/profile-step-statistics";
import { profileStatisticsContextSchema } from "@/lib/types/profiles/profile-step-statistics";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { fightRecordFactSchema, type FightRecordFact, type ProfileHistoryPage } from "@/lib/types/profiles/profile-results";
import {
    profileCountRowSchema, profileIdentifierRowSchema, profileUserIDSchema, activityDaySchema, defaultProfileSettings, profileAccessRowSchema, profileFeatureConfigSchema,
    profileSettingsSchema, profileSharedFightRowSchema, sharedProfileSchema,
    type ProfilePageQuery, type ProfilePreviewAudience, type ProfileSettings,
    type SharedIdentity, type SharedProfile, type UpdateProfileSettings, type ProfileRivalrySummary,
} from "@/lib/types/profiles/shared-profile";
import { signMediaUrl, signMediaUrls } from "./media-supabase-query";

/** Profile locks serialize new sharing reads with settings, friendships, blocks, and deletion. */
export async function loadProfileAccess(sql: TransactionSql, viewerId: string, targetId: string, write = false) {
    const users = await sql`
        select id as user_id from public.profiles
        where id in (${viewerId}, ${targetId}) and deleted_at is null
        order by user_id ${write ? sql`for update` : sql`for share`}
    `;
    if (users.length !== (viewerId === targetId ? 1 : 2)) {
        throw new ApiError(404, "not_found", "Profile unavailable");
    }
    const [result] = await loadProfileAccessRows(sql, viewerId, [targetId]);
    if (result.relationship.blocked) throw new ApiError(404, "not_found", "Profile unavailable");
    return result;
}

/** Callers lock the viewer and every target first, as loadProfileAccess does. */
async function loadProfileAccessRows(sql: TransactionSql, viewerId: string, targetIds: string[]) {
    return profileAccessRowSchema.array().parse(await sql`
        select jsonb_build_object('user_id', profile.id, 'handle', profile.handle,
            'display_name', profile.display_name, 'companion_id', profile.companion_id) identity,
            case when profile.companion_id = 'custom' then profile.companion_image_url end companion_image_url,
            media.object_path avatar_path, coalesce(profile.time_zone, 'UTC') time_zone,
            coalesce(to_jsonb(settings), ${sql.json(defaultProfileSettings)}::jsonb) settings,
            jsonb_build_object(
                'owner', profile.id = ${viewerId},
                'friend', coalesce(friendship.state = 'accepted', false),
                'current_opponent', exists (
                    select 1 from public.fight_members mine
                    join public.fight_members theirs on theirs.fight_id = mine.fight_id
                    join public.fights fight on fight.id = mine.fight_id
                    where mine.user_id = ${viewerId} and theirs.user_id = profile.id
                        and mine.state = 'accepted' and theirs.state = 'accepted'
                        and fight.starts_at <= now()
                        and fight.state in ('live', 'awaiting_final_sync')
                        and now() < fight.ends_at + fight.final_sync_grace_seconds * interval '1 second'
                ),
                'blocked', exists (
                    select 1 from (
                        select blocker_id, blocked_id from private.profile_blocks
                        union all select blocker_id, blocked_id from private.feed_blocks
                        union all select blocker_id, blocked_id from private.feedback_blocks
                    ) blocks where (blocker_id = ${viewerId} and blocked_id = profile.id)
                        or (blocker_id = profile.id and blocked_id = ${viewerId})
                )
            ) relationship,
            case when profile.id = ${viewerId} then 'self'
                when friendship.state = 'accepted' then 'friends'
                when friendship.requester_id = ${viewerId} then 'outgoing'
                when friendship.requester_id is not null then 'incoming' else 'none' end friendship
        from public.profiles profile
        left join private.profile_settings settings on settings.user_id = profile.id
        left join public.media_objects media on media.id = profile.avatar_media_id and media.status = 'ready'
        left join private.profile_friendships friendship
            on friendship.user_low = least(${viewerId}::uuid, profile.id)
            and friendship.user_high = greatest(${viewerId}::uuid, profile.id)
        where profile.id = any(${sql.array(targetIds)}::uuid[])
    `);
}

/**
 * Captured member facts remain readable after leaving a recurring series. A page starts at its
 * cursor row, inclusive, so the caller can reject a cursor that is not in the eligible list.
 */
export async function loadProfileFightFacts(
    sql: TransactionSql, userId: string, page?: { fightIds: string[] | null; cursor: string | undefined; rows: number },
): Promise<FightRecordFact[]> {
    return fightRecordFactSchema.array().parse(await sql`
        select fight.id, mine.history_id, fight.state::text, fight.starts_at::text, fight.ends_at::text,
            extract(epoch from ((fight.ends_at at time zone fight.time_zone)
                - (fight.starts_at at time zone fight.time_zone)))::float8 / 86400 as calendar_days,
            context.category, context.result_summary summary, fight.name, fight.action_text, fight.outcome_rule::text,
            (select jsonb_agg(jsonb_build_object(
                'user_id', member.user_id, 'entered_at', member.entered_at,
                'departed_at', member.departed_at, 'departure', member.departure,
                'state', member.state, 'rank', member.rank, 'final_value', member.final_value,
                'complete', member.complete, 'finalized_at', member.finalized_at, 'reliable', member.reliable
            ) order by member.user_id) from private.fight_participation_records member
                where member.fight_id = fight.id) members
        from public.fights fight
        join private.fight_record_contexts context on context.fight_id = fight.id
        join private.fight_participation_records mine on mine.fight_id = fight.id
        where mine.user_id = ${userId}
            ${page?.fightIds ? sql`and fight.id = any(${sql.array(page.fightIds)}::uuid[])` : sql``}
            ${page?.cursor ? sql`and (fight.ends_at, fight.id) <= (
                select cursor_fight.ends_at, cursor_fight.id from private.fight_participation_records cursor_member
                join public.fights cursor_fight on cursor_fight.id = cursor_member.fight_id
                where cursor_member.user_id = ${userId} and cursor_member.history_id = ${page.cursor}
            )` : sql``}
        order by fight.ends_at desc, fight.id desc
        ${page ? sql`limit ${page.rows}` : sql``}
    `);
}

async function loadSharedFightIds(sql: TransactionSql, viewerId: string, targetIds: string[]) {
    return profileSharedFightRowSchema.array().parse(await sql`
        select theirs.user_id, mine.fight_id as id from public.fight_members mine
        join public.fight_members theirs on theirs.fight_id = mine.fight_id
        join public.fights fight on fight.id = mine.fight_id
        where mine.user_id = ${viewerId} and theirs.user_id = any(${sql.array(targetIds)}::uuid[])
            and mine.state in ('accepted', 'deferred') and theirs.state in ('accepted', 'deferred')
            and (fight.series_id is null or exists (
                select 1 from public.fight_series_members my_series
                join public.fight_series_members their_series on their_series.series_id = my_series.series_id
                where my_series.series_id = fight.series_id
                    and my_series.user_id = ${viewerId} and their_series.user_id = theirs.user_id
                    and my_series.state in ('accepted', 'deferred') and their_series.state in ('accepted', 'deferred')
            ))
    `);
}

export async function readSharedProfile(
    viewerId: string, targetId: string, preview?: ProfilePreviewAudience,
    database: Sql = createDatabaseClient(),
): Promise<SharedProfile> {
    if (preview && viewerId !== targetId) throw new ApiError(403, "forbidden", "Preview your own profile");
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, viewerId, targetId);
        const relationship = preview ? {
            owner: false, blocked: false, friend: preview === "friend", current_opponent: preview === "opponent",
        } : row.relationship;
        const access = profileAccess(row.settings, relationship);
        const facts = access.record ? await loadProfileFightFacts(sql, targetId) : [];
        const rivalry = access.record && !relationship.owner && !preview
            ? rivalryRecord(facts, viewerId, targetId, new Set((await loadSharedFightIds(sql, viewerId, [targetId])).map((fight) => fight.id)))
            : null;
        const [contextRow] = await sql`
            select (now() at time zone ${row.time_zone})::date::text today, ${row.time_zone}::text time_zone
        `;
        const context = profileStatisticsContextSchema.parse(contextRow);
        const values = access.activity ? activityDaySchema.array().parse(await sql`
            with days as (
                select metric.day, metric.value, metric.time_zone, metric.updated_at,
                    metric.observed_through >= metric.ends_at as finalized, 1 as priority
                from private.activity_metrics as metric
                join public.data_sources as source on source.id = metric.source_id
                where metric.user_id = ${targetId} and metric.scope = 'day' and metric.metric = 'steps'
                    and source.provider = 'apple_health'
                union all
                select legacy.day, legacy.value, legacy.time_zone, legacy.updated_at,
                    legacy.finalized_at is not null as finalized, 0 as priority
                from public.metric_days as legacy
                join public.data_sources as source on source.id = legacy.source_id
                where legacy.user_id = ${targetId} and legacy.metric = 'steps'
                    and source.provider = 'apple_health'
            )
            select distinct on (days.day) days.day::text, days.value::float8 steps,
                days.time_zone, days.updated_at::text, days.finalized
            from days
            where days.day >= ${context.today}::date - ${row.settings.activity_days - 1}::integer
                and days.day <= ${context.today}::date
            order by days.day, days.updated_at desc, days.priority desc
        `) : [];
        let statistics: SharedProfile["step_statistics"] = null;
        if (access.activity) {
            const history = relationship.owner ? activityDaySchema.array().parse(await sql`
                with days as (
                    select metric.day, metric.value, metric.time_zone, metric.updated_at,
                        metric.observed_through >= metric.ends_at as finalized, 1 as priority
                    from private.activity_metrics as metric
                    join public.data_sources as source on source.id = metric.source_id
                    where metric.user_id = ${targetId} and metric.scope = 'day' and metric.metric = 'steps'
                        and source.provider = 'apple_health'
                    union all
                    select legacy.day, legacy.value, legacy.time_zone, legacy.updated_at,
                        legacy.finalized_at is not null as finalized, 0 as priority
                    from public.metric_days as legacy
                    join public.data_sources as source on source.id = legacy.source_id
                    where legacy.user_id = ${targetId} and legacy.metric = 'steps'
                        and source.provider = 'apple_health'
                )
                select distinct on (days.day) days.day::text, days.value::float8 steps,
                    days.time_zone, days.updated_at::text, days.finalized
                from days
                order by days.day, days.updated_at desc, days.priority desc
            `) : values;
            statistics = profileStepStatistics(history, context, relationship.owner ? null : row.settings.activity_days);
        }
        return sharedProfileSchema.parse({
            identity: { ...row.identity, avatar_url: row.companion_image_url ?? (row.avatar_path ? await signMediaUrl(row.avatar_path) : null) },
            access: relationship.owner ? "owner" : access.shared ? "shared" : "private",
            competitive: row.settings.competitive,
            friendship: preview ? "none" : row.friendship,
            record: access.record ? profileRecord(facts, targetId) : null,
            rivalry,
            activity: access.activity ? { metric: "steps", days: row.settings.activity_days, values } : null,
            step_statistics: statistics,
            artwork: null,
            view_measurement_enabled: !preview && access.shared && profileFeatureConfigSchema.parse({
                measurement: process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED,
            }).measurement,
        });
    });
}

export async function readProfileHistory(
    viewerId: string, targetId: string, query: ProfilePageQuery, database: Sql = createDatabaseClient(),
): Promise<ProfileHistoryPage> {
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, viewerId, targetId);
        const access = profileAccess(row.settings, row.relationship);
        if (!access.record && query.shared !== "true") throw new ApiError(403, "forbidden", "This record is private");
        const sharedIds = query.shared === "true" ? (await loadSharedFightIds(sql, viewerId, [targetId])).map((fight) => fight.id) : null;
        // A cursor page also returns the cursor row first; one more row shows whether another page follows.
        const facts = await loadProfileFightFacts(sql, targetId, {
            fightIds: sharedIds, cursor: query.cursor, rows: query.limit + (query.cursor ? 2 : 1),
        });
        if (query.cursor && facts.shift()?.history_id !== query.cursor) throw new ApiError(400, "validation", "Invalid history cursor");
        const page = facts.slice(0, query.limit);
        const visible = profileIdentifierRowSchema.array().parse(await sql`
            select fight_id as id from public.fight_members
            where user_id = ${viewerId} and state in ('accepted', 'deferred')
                and fight_id = any(${sql.array(page.map((fight) => fight.id))}::uuid[])
        `);
        const visibleIds = new Set(visible.map((member) => member.id));
        return {
            results: page.map((fight) => {
                const result = classifyFightResult(fight, targetId);
                const hasDetail = visibleIds.has(fight.id);
                return {
                    id: fight.history_id, fight_id: hasDetail ? fight.id : null, name: hasDetail ? fight.name : null,
                    starts_at: fight.starts_at, ends_at: fight.ends_at, category: fight.category,
                    result: result.result, placement: result.placement, field_size: result.fieldSize,
                    counted: result.counted,
                    complete: fight.members.find((member) => member.user_id === targetId)!.complete,
                };
            }),
            next_cursor: facts.length > query.limit ? page[page.length - 1].history_id : null,
        };
    });
}

export async function readProfileSettings(userId: string, database: Sql = createDatabaseClient()): Promise<ProfileSettings> {
    return database.begin(async (sql) => (await loadProfileAccess(sql, userId, userId)).settings);
}

export async function updateProfileSettings(userId: string, input: UpdateProfileSettings, database: Sql = createDatabaseClient()): Promise<ProfileSettings> {
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, userId, userId, true);
        const next = { ...row.settings, ...input, revision: row.settings.revision + 1 };
        if (next.activity_audience === "public" && next.audience !== "public") {
            if (input.activity_audience === "public") throw new ApiError(400, "validation", "Public Steps sharing requires a public profile");
            next.activity_audience = "off";
        }
        if (next.artwork_allowed) throw new ApiError(409, "conflict", "Artwork sharing is not available yet");
        await sql`
            insert into private.profile_settings ${sql({ user_id: userId, ...next })}
            on conflict (user_id) do update set competitive = excluded.competitive, audience = excluded.audience,
                activity_audience = excluded.activity_audience, activity_days = excluded.activity_days,
                artwork_allowed = excluded.artwork_allowed, revision = excluded.revision, updated_at = now()
        `;
        await sql`
            update private.rivalry_artworks set state = 'cancelled', hidden = true
            where (user_low = ${userId} or user_high = ${userId}) and state <> 'cancelled'
        `;
        return profileSettingsSchema.parse(next);
    });
}

export async function lookupSharedProfile(userId: string, handle: string, database: Sql = createDatabaseClient()): Promise<SharedIdentity> {
    const targetId = await database.begin(async (sql) => {
        await sql`select id as user_id from public.profiles where id = ${userId} for update`;
        const [count] = await sql`select count(*)::int n from private.profile_lookup_attempts
            where actor_id = ${userId} and created_at > now() - interval '1 hour'`;
        if (profileCountRowSchema.parse(count).n >= 30) throw new ApiError(429, "rate_limited", "Too many username searches");
        await sql`insert into private.profile_lookup_attempts(actor_id) values (${userId})`;
        const [profile] = await sql`select id as user_id from public.profiles where lower(handle) = ${handle} and deleted_at is null`;
        return profile ? profileUserIDSchema.parse(profile.user_id) : null;
    });
    if (!targetId) throw new ApiError(404, "not_found", "Profile unavailable");
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, userId, targetId);
        return { ...row.identity, avatar_url: row.companion_image_url ?? (row.avatar_path ? await signMediaUrl(row.avatar_path) : null) };
    });
}

/**
 * The six most recent eligible opponents, with each target's current sharing checked as a Profile
 * read would. A duel's facts are the same from either side, so the viewer's facts score every rivalry.
 */
export async function readOwnRivalries(userId: string, database: Sql = createDatabaseClient()): Promise<ProfileRivalrySummary[]> {
    const facts = await database.begin(async (sql) => {
        await loadProfileAccess(sql, userId, userId);
        return loadProfileFightFacts(sql, userId);
    });
    const candidates = new Set<string>();
    for (const fight of facts) {
        const ownResult = classifyFightResult(fight, userId);
        if (!ownResult.counted || ownResult.fieldSize !== 2) continue;
        for (const member of fight.members) {
            if (member.user_id !== userId && classifyFightResult(fight, member.user_id).counted) candidates.add(member.user_id);
        }
    }
    if (candidates.size === 0) return [];
    const rivals = await database.begin(async (sql) => {
        // NOTE: One ordered lock statement cannot deadlock with writers that lock a profile pair in order.
        const present = new Set(profileIdentifierRowSchema.array().parse(await sql`
            select id from public.profiles
            where id = any(${sql.array([userId, ...candidates])}::uuid[]) and deleted_at is null
            order by id for share
        `).map((row) => row.id));
        if (!present.has(userId)) return [];
        const rows = new Map((await loadProfileAccessRows(sql, userId, [...candidates].filter((id) => present.has(id))))
            .map((row) => [row.identity.user_id, row]));
        const eligible = [...candidates].flatMap((id) => {
            const row = rows.get(id);
            return row && profileAccess(row.settings, row.relationship).record ? [row] : [];
        }).slice(0, 6);
        const shared = await loadSharedFightIds(sql, userId, eligible.map((row) => row.identity.user_id));
        return eligible.map((row) => ({
            row,
            sharedIds: new Set(shared.filter((fight) => fight.user_id === row.identity.user_id).map((fight) => fight.id)),
        }));
    });
    const avatars = await signMediaUrls(rivals.flatMap(({ row }) => !row.companion_image_url && row.avatar_path ? [row.avatar_path] : []));
    return rivals.map(({ row, sharedIds }) => ({
        identity: { ...row.identity, avatar_url: row.companion_image_url ?? (row.avatar_path ? avatars.get(row.avatar_path) ?? null : null) },
        rivalry: rivalryRecord(facts, userId, row.identity.user_id, sharedIds),
    }));
}
