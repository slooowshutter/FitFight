import { z } from "zod";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    fightSnapshotSchema,
    snapshotFriendshipsRowSchema,
    type FightSnapshot,
} from "@/lib/types/fights/fight-snapshot";
import { companionIdSchema } from "@/lib/types/companions/companion";
import { FRIEND_FIGHT_WEEK_SECONDS } from "@/lib/types/fights/friend-fight";
import { mapMedia, signMediaUrls, type MediaRow } from "./media-supabase-query";

const snapshotRowSchema = fightSnapshotSchema.extend({
    fights: z.array(
        fightSnapshotSchema.shape.fights.element.extend({ friends: z.boolean() }),
    ),
    friends: fightSnapshotSchema.shape.friends.unwrap(),
    profiles: z.array(
        z.object({
            user_id: z.string().uuid(),
            handle: z.string(),
            display_name: z.string(),
            avatar_media_id: z.string().uuid().nullable().optional(),
            companion_id: companionIdSchema.nullable().default(null),
            companion_image_url: z.string().url().nullish(),
        }),
    ),
});

/** Read with the caller's RLS policies; the pooler's server role must not broaden visibility. */
export async function readFightSnapshot(
    userId: string,
    timeZone: string,
    database: Sql = createDatabaseClient(),
    hosted = false,
    friends = false,
): Promise<FightSnapshot> {
    const row = await database.begin("read only", async (sql) => {
        // NOTE: friendships are private and the reader role cannot see them, so read the caller's
        // friends and incoming requests (as GET /friends lists them) before dropping to that role.
        const [friendshipsRow] = await sql`
            select count(*) filter (
                    where friendship.state = 'pending' and friendship.requester_id <> ${userId}
                )::int as requests,
                coalesce(array_agg(profile.id) filter (where friendship.state = 'accepted'), '{}') as friend_ids
            from private.profile_friendships as friendship
            join public.profiles as profile on profile.id = case when friendship.user_low = ${userId}
                then friendship.user_high else friendship.user_low end
            where (friendship.user_low = ${userId} or friendship.user_high = ${userId})
                and profile.deleted_at is null
                and not exists (
                    select 1 from (
                        select blocker_id, blocked_id from private.profile_blocks
                        union all select blocker_id, blocked_id from private.feed_blocks
                        union all select blocker_id, blocked_id from private.feedback_blocks
                    ) as blocks where (blocker_id = ${userId} and blocked_id = profile.id)
                        or (blocker_id = profile.id and blocked_id = ${userId})
                )
        `;
        const friendships = snapshotFriendshipsRowSchema.parse(friendshipsRow);
        await sql`set local role fitfight_backend_reader`;
        await sql`
            select set_config('request.jwt.claim.sub', ${userId}, true),
                set_config('request.jwt.claims', ${JSON.stringify({ sub: userId, role: "authenticated" })}, true)
        `;
        const [result] = await sql<{ snapshot: unknown }[]>`
            with visible_fights as materialized (
                select id, owner_id, name, state, starts_at, ends_at, time_zone, action_text, series_id, friends,
                    -- null: the Fight waits for everyone's final Steps.
                    case when closes_after_grace
                        then ends_at + final_sync_grace_seconds * interval '1 second' end as grace_ends_at,
                    (
                        select coalesce(image.webp_url, image.image_url) from private.fight_group_images as image
                        where image.fight_id = fight.id and image.status = 'ready'
                        order by image.finished_at desc
                        limit 1
                    ) as group_image_url
                from public.fights as fight
                where ${hosted
                    // ponytail: every current hosted round in one payload; page it if a host has thousands.
                    ? sql`fight.host_id = ${userId} and fight.state in ('live', 'awaiting_final_sync')
                        and (
                            select count(*) from public.fight_members as racer
                            where racer.fight_id = fight.id and racer.user_id in (fight.owner_id, fight.host_id)
                                and racer.state = 'accepted'
                        ) = 2`
                    : friends
                    // Every round with each current friend that was not cancelled: the live one, and
                    // the ended ones for the fight's History.
                    // ponytail: the whole history in one payload, about 52 rounds a year for a weekly
                    // pair; page ended rounds by date if a payload gets heavy.
                    ? sql`fight.friends and fight.state in ('live', 'awaiting_final_sync', 'final')
                        and fight.id in (
                            select fight_id from public.fight_members where user_id = ${userId} and state = 'accepted'
                        )
                        and exists (
                            select 1 from public.fight_members as friend
                            where friend.fight_id = fight.id and friend.state = 'accepted'
                                and friend.user_id = any(${sql.array(friendships.friend_ids)}::uuid[])
                        )`
                    : sql`not fight.friends and fight.host_id is distinct from ${userId}
                        and fight.id in (
                            select id from public.fights where owner_id = ${userId}
                            union
                            select fight_id from public.fight_members where user_id = ${userId}
                        )`}
            ), visible_members as materialized (
                select member.fight_id, member.user_id, member.state, member.current_value,
                    member.rank, member.final_value, member.last_synced_at, member.final_steps_complete,
                    case when history.value = coalesce(member.current_value, member.final_value)
                        then history.step_checkpoints end as step_checkpoints
                from public.fight_members as member
                left join lateral (
                    select snapshot.value, snapshot.step_checkpoints
                    from private.fight_score_snapshots as snapshot
                    where snapshot.fight_id = member.fight_id and snapshot.user_id = member.user_id
                        and snapshot.source_id = member.selected_source_id
                        and (member.finalized_at is null or snapshot.is_final)
                    order by snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
                    limit 1
                ) as history on member.state = 'accepted'
                where member.fight_id in (select id from visible_fights)
            ), visible_profiles as (
                select id as user_id, handle, display_name, avatar_media_id, companion_id, companion_image_url
                from public.profiles
                where id in (
                    select user_id from visible_members union select owner_id from visible_fights
                )
            ), visible_series as (
                select id, join_code, visibility, recurring, suggested,
                    case when friend_low is null then null
                        when duration_seconds = ${FRIEND_FIGHT_WEEK_SECONDS} then 'week' else 'month' end
                        as friend_round_length
                from public.fight_series
                where id in (select series_id from visible_fights)
            ), chart_bounds as (
                select min((starts_at at time zone ${timeZone})::date) as first_day,
                    max(least(
                        ((ends_at - interval '1 microsecond') at time zone ${timeZone})::date,
                        (starts_at at time zone ${timeZone})::date + 40
                    )) as last_day
                from visible_fights
            ), shared_windows as materialized (
                -- NOTE: materialized keeps these bounds plain dates. Inlined, the non-leakproof
                -- "at time zone" would run after step_days RLS instead of as an index condition.
                select racer.user_id,
                    (fight.starts_at at time zone fight.time_zone)::date as starts_on,
                    ((fight.ends_at - interval '1 microsecond') at time zone fight.time_zone)::date as ends_on
                from visible_members as viewer
                join visible_members as racer on racer.fight_id = viewer.fight_id and racer.state = 'accepted'
                join visible_fights as fight on fight.id = viewer.fight_id
                where viewer.user_id = ${userId} and viewer.state in ('accepted', 'deferred')
            ), visible_days as (
                -- Same rows step_days_select_self_or_fight admits in the chart window: the caller's
                -- own days, plus accepted racers' days inside a Fight the caller races or sits out.
                select user_id, day, steps
                from public.step_days
                where user_id = ${userId}
                    and user_id in (select user_id from visible_members)
                    and day between (select first_day from chart_bounds) and (select last_day from chart_bounds)
                union
                select step.user_id, step.day, step.steps
                from shared_windows
                join public.step_days as step on step.user_id = shared_windows.user_id
                    and step.day between shared_windows.starts_on and shared_windows.ends_on
                where step.day between (select first_day from chart_bounds) and (select last_day from chart_bounds)
            )
            select jsonb_build_object(
                'fights', coalesce((select jsonb_agg(to_jsonb(f) order by starts_at, id) from visible_fights f), '[]'::jsonb),
                'members', coalesce((select jsonb_agg(to_jsonb(m) order by fight_id, user_id) from visible_members m), '[]'::jsonb),
                'profiles', coalesce((select jsonb_agg(to_jsonb(p) order by user_id) from visible_profiles p), '[]'::jsonb),
                'series', coalesce((select jsonb_agg(to_jsonb(s) order by id) from visible_series s), '[]'::jsonb),
                'step_days', coalesce((select jsonb_agg(to_jsonb(d) order by day, user_id) from visible_days d), '[]'::jsonb),
                'hosted', (
                    select jsonb_build_object(
                        'name', min(series.name), 'rounds', count(*),
                        'leading', count(*) filter (
                            where coalesce(host.current_value, 0) > coalesce(challenger.current_value, 0)
                        )
                    )
                    from public.fights as fight
                    join public.fight_series as series on series.id = fight.series_id
                    join public.fight_members as host
                        on host.fight_id = fight.id and host.user_id = fight.host_id and host.state = 'accepted'
                    join public.fight_members as challenger
                        on challenger.fight_id = fight.id and challenger.user_id = fight.owner_id
                        and challenger.state = 'accepted'
                    where fight.host_id = ${userId} and fight.state in ('live', 'awaiting_final_sync')
                    having count(*) > 0
                ),
                'friends', (
                    select jsonb_build_object(
                        'rounds', count(*),
                        'leading', count(*) filter (
                            where coalesce(caller.current_value, 0) > coalesce(friend.current_value, 0)
                        ),
                        'requests', ${friendships.requests}::int
                    )
                    from public.fights as fight
                    join public.fight_members as caller
                        on caller.fight_id = fight.id and caller.user_id = ${userId} and caller.state = 'accepted'
                    join public.fight_members as friend
                        on friend.fight_id = fight.id and friend.state = 'accepted'
                        and friend.user_id = any(${sql.array(friendships.friend_ids)}::uuid[])
                    where fight.friends and fight.state = 'live' and fight.ends_at > now()
                )
            ) as snapshot
        `;
        return snapshotRowSchema.parse(result.snapshot);
    });
    return fightSnapshotSchema.parse({
        ...row,
        profiles: await attachProfileAvatars(row.profiles),
    });
}

async function attachProfileAvatars(
    profiles: z.infer<typeof snapshotRowSchema>["profiles"],
): Promise<FightSnapshot["profiles"]> {
    const ids = [
        ...new Set(
            profiles.flatMap((profile) =>
                profile.avatar_media_id ? [profile.avatar_media_id] : [],
            ),
        ),
    ];
    const avatars = new Map<
        string,
        FightSnapshot["profiles"][number]["avatar"]
    >();
    if (ids.length > 0) {
        const admin = createAdminClient();
        const { data, error } = await admin
            .from("media_objects")
            .select(
                "id, owner_id, kind, purpose, status, object_path, original_filename, content_type, byte_size, width, height, duration_ms, sha256, created_at",
            )
            .in("id", ids)
            .eq("status", "ready");
        if (error)
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load profile photos",
            );
        const mediaRows = (data ?? []) as MediaRow[];
        const urls = await signMediaUrls(
            mediaRows.map((media) => media.object_path),
        );
        for (const media of mediaRows) {
            avatars.set(
                media.id,
                mapMedia(media, urls.get(media.object_path) ?? null),
            );
        }
    }
    return profiles.map((profile) => ({
        user_id: profile.user_id,
        handle: profile.handle,
        display_name: profile.display_name,
        avatar: profile.avatar_media_id
            ? (avatars.get(profile.avatar_media_id) ?? null)
            : null,
        companion_id: profile.companion_id,
        ...(profile.companion_id === "custom" && profile.companion_image_url ? { companion_image_url: profile.companion_image_url } : {}),
    }));
}
