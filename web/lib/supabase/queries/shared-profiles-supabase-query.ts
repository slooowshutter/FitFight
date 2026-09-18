import type { Sql, TransactionSql } from "postgres";
import { profileAccess } from "@/lib/domain/profiles/profile-access";
import { classifyFightResult, profileRecord, rivalryRecord } from "@/lib/domain/profiles/profile-results";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { fightRecordFactSchema, type FightRecordFact, type ProfileHistoryPage } from "@/lib/types/profiles/profile-results";
import {
    profileCountRowSchema, profileIdentifierRowSchema, profileUserIDSchema, activityDaySchema, defaultProfileSettings, profileAccessRowSchema, profileFeatureConfigSchema,
    profileSettingsSchema, sharedProfileSchema,
    type ProfilePageQuery, type ProfilePreviewAudience, type ProfileSettings,
    type SharedIdentity, type SharedProfile, type UpdateProfileSettings, type ProfileRivalrySummary,
} from "@/lib/types/profiles/shared-profile";
import { signMediaUrl } from "./media-supabase-query";

/** Profile locks serialize new sharing reads with settings, friendships, blocks, and deletion. */
export async function loadProfileAccess(sql: TransactionSql, viewerId: string, targetId: string, write = false) {
    const users = await sql`
        select user_id from public.profiles
        where user_id in (${viewerId}, ${targetId}) and deleted_at is null
        order by user_id ${write ? sql`for update` : sql`for share`}
    `;
    if (users.length !== (viewerId === targetId ? 1 : 2)) {
        throw new ApiError(404, "not_found", "Profile unavailable");
    }
    const [row] = await sql`
        select jsonb_build_object('user_id', profile.user_id, 'handle', profile.handle,
            'display_name', profile.display_name, 'companion_id', profile.companion_id) identity,
            media.object_path avatar_path,
            coalesce(to_jsonb(settings), ${sql.json(defaultProfileSettings)}::jsonb) settings,
            jsonb_build_object(
                'owner', profile.user_id = ${viewerId},
                'friend', coalesce(friendship.state = 'accepted', false),
                'current_opponent', exists (
                    select 1 from public.fight_members mine
                    join public.fight_members theirs on theirs.fight_id = mine.fight_id
                    join public.fights fight on fight.id = mine.fight_id
                    where mine.user_id = ${viewerId} and theirs.user_id = ${targetId}
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
                    ) blocks where (blocker_id = ${viewerId} and blocked_id = ${targetId})
                        or (blocker_id = ${targetId} and blocked_id = ${viewerId})
                )
            ) relationship,
            case when profile.user_id = ${viewerId} then 'self'
                when friendship.state = 'accepted' then 'friends'
                when friendship.requester_id = ${viewerId} then 'outgoing'
                when friendship.requester_id is not null then 'incoming' else 'none' end friendship
        from public.profiles profile
        left join private.profile_settings settings on settings.user_id = profile.user_id
        left join public.media_objects media on media.id = profile.avatar_media_id and media.status = 'ready'
        left join private.profile_friendships friendship
            on friendship.user_low = least(${viewerId}::uuid, ${targetId}::uuid)
            and friendship.user_high = greatest(${viewerId}::uuid, ${targetId}::uuid)
        where profile.user_id = ${targetId}
    `;
    const result = profileAccessRowSchema.parse(row);
    if (result.relationship.blocked) throw new ApiError(404, "not_found", "Profile unavailable");
    return result;
}

/** Captured member facts remain readable after leaving a recurring series. */
export async function loadProfileFightFacts(sql: TransactionSql, userId: string): Promise<FightRecordFact[]> {
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
        join private.fight_participation_records mine on mine.fight_id = fight.id and mine.user_id = ${userId}
        order by fight.ends_at desc, fight.id desc
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
        const values = access.activity ? activityDaySchema.array().parse(await sql`
            select distinct on (days.day) days.day::text, days.value::float8 steps,
                days.time_zone, days.updated_at::text, (days.finalized_at is not null) finalized
            from public.metric_days days
            join public.data_sources source on source.id = days.source_id
            where days.user_id = ${targetId} and days.metric = 'steps'
                and source.provider = 'apple_health'
                and days.day >= (now() at time zone coalesce(days.time_zone, 'UTC'))::date - ${row.settings.activity_days - 1}::integer
                and days.day <= (now() at time zone coalesce(days.time_zone, 'UTC'))::date
            order by days.day, days.updated_at desc
        `) : [];
        return sharedProfileSchema.parse({
            identity: { ...row.identity, avatar_url: row.avatar_path ? await signMediaUrl(row.avatar_path) : null },
            access: relationship.owner ? "owner" : access.shared ? "shared" : "private",
            competitive: row.settings.competitive,
            friendship: preview ? "none" : row.friendship,
            record: access.record ? profileRecord(facts, targetId) : null,
            rivalry: access.record && !relationship.owner && !preview ? rivalryRecord(facts, viewerId, targetId) : null,
            activity: access.activity ? { metric: "steps", days: row.settings.activity_days, values } : null,
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
        const facts = await loadProfileFightFacts(sql, targetId);
        const eligible = facts.filter((fight) => query.shared !== "true" || fight.members.some((member) => member.user_id === viewerId
            && member.entered_at !== null));
        const cursorIndex = query.cursor ? eligible.findIndex((fight) => fight.history_id === query.cursor) : -1;
        if (query.cursor && cursorIndex === -1) throw new ApiError(400, "validation", "Invalid history cursor");
        const page = eligible.slice(cursorIndex + 1, cursorIndex + 1 + query.limit);
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
            next_cursor: cursorIndex + 1 + query.limit < eligible.length ? page[page.length - 1].history_id : null,
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
        await sql`select user_id from public.profiles where user_id = ${userId} for update`;
        const [count] = await sql`select count(*)::int n from private.profile_lookup_attempts
            where actor_id = ${userId} and created_at > now() - interval '1 hour'`;
        if (profileCountRowSchema.parse(count).n >= 30) throw new ApiError(429, "rate_limited", "Too many username searches");
        await sql`insert into private.profile_lookup_attempts(actor_id) values (${userId})`;
        const [profile] = await sql`select user_id from public.profiles where lower(handle) = ${handle} and deleted_at is null`;
        return profile ? profileUserIDSchema.parse(profile.user_id) : null;
    });
    if (!targetId) throw new ApiError(404, "not_found", "Profile unavailable");
    return database.begin(async (sql) => {
        const row = await loadProfileAccess(sql, userId, targetId);
        return { ...row.identity, avatar_url: row.avatar_path ? await signMediaUrl(row.avatar_path) : null };
    });
}

/** The six most recent eligible opponents, with each target's current sharing checked separately. */
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
    const summaries: ProfileRivalrySummary[] = [];
    for (const targetId of candidates) {
        try {
            const profile = await readSharedProfile(userId, targetId, undefined, database);
            if (profile.rivalry && profile.rivalry.wins + profile.rivalry.losses + profile.rivalry.draws > 0) {
                summaries.push({ identity: profile.identity, rivalry: profile.rivalry });
            }
        } catch (error) {
            if (!(error instanceof ApiError) || error.status !== 404) throw error;
        }
        if (summaries.length === 6) break;
    }
    return summaries;
}
