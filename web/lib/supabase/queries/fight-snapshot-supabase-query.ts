import { z } from "zod";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    fightSnapshotSchema,
    type FightSnapshot,
} from "@/lib/types/fights/fight-snapshot";
import { companionIdSchema } from "@/lib/types/companions/companion";
import { mapMedia, signMediaUrls, type MediaRow } from "./media-supabase-query";

const snapshotRowSchema = fightSnapshotSchema.extend({
    profiles: z.array(
        z.object({
            user_id: z.string().uuid(),
            handle: z.string(),
            display_name: z.string(),
            avatar_media_id: z.string().uuid().nullable().optional(),
            companion_id: companionIdSchema.nullable().default(null),
        }),
    ),
});

/** Read with the caller's RLS policies; the pooler's server role must not broaden visibility. */
export async function readFightSnapshot(
    userId: string,
    timeZone: string,
    database: Sql = createDatabaseClient(),
): Promise<FightSnapshot> {
    const row = await database.begin("read only", async (sql) => {
        await sql`set local role fitfight_backend_reader`;
        await sql`
            select set_config('request.jwt.claim.sub', ${userId}, true),
                set_config('request.jwt.claims', ${JSON.stringify({ sub: userId, role: "authenticated" })}, true)
        `;
        const [result] = await sql<{ snapshot: unknown }[]>`
            with visible_fights as materialized (
                select id, owner_id, name, state, starts_at, ends_at, action_text, series_id,
                    (ends_at + (final_sync_grace_seconds * interval '1 second')) as grace_ends_at
                from public.fights
                where owner_id = ${userId}
                    or id in (select fight_id from public.fight_members where user_id = ${userId})
            ), visible_members as materialized (
                select member.fight_id, member.user_id, member.state, member.current_value,
                    member.rank, member.final_value, member.last_synced_at, member.final_steps_complete,
                    case when history.value = coalesce(member.current_value, member.final_value)
                        then history.step_checkpoints end as step_checkpoints
                from public.fight_members as member
                left join lateral (
                    select snapshot.value,
                        case
                            when snapshot.step_checkpoints is not null then snapshot.step_checkpoints
                            else (
                                select case
                                    when points.step_checkpoints is null then null
                                    when (points.step_checkpoints -> -1 ->> 'steps')::numeric
                                        = snapshot.value
                                        then points.step_checkpoints
                                    else points.step_checkpoints || jsonb_build_array(
                                        jsonb_build_object(
                                            'day', to_char(
                                                (snapshot.cutoff_at
                                                    at time zone coalesce(fight.time_zone, 'UTC')
                                                )::date,
                                                'YYYY-MM-DD'
                                            ),
                                            'cutoff_at', trim(both '"' from to_jsonb(snapshot.cutoff_at)::text),
                                            'steps', round(snapshot.value)::integer
                                        )
                                    )
                                end
                                from (
                                    select jsonb_agg(
                                        jsonb_build_object(
                                            'day', scored.day,
                                            'cutoff_at', scored.cutoff_at,
                                            'steps', scored.steps
                                        )
                                        order by scored.day
                                    ) as step_checkpoints
                                    from (
                                        select distinct on (
                                            (point.cutoff_at
                                                at time zone coalesce(fight.time_zone, 'UTC')
                                            )::date
                                        )
                                            to_char(
                                                (point.cutoff_at
                                                    at time zone coalesce(fight.time_zone, 'UTC')
                                                )::date,
                                                'YYYY-MM-DD'
                                            ) as day,
                                            trim(both '"' from to_jsonb(point.cutoff_at)::text)
                                                as cutoff_at,
                                            round(point.value)::integer as steps
                                        from private.fight_score_snapshots as point
                                        where point.fight_id = snapshot.fight_id
                                            and point.user_id = snapshot.user_id
                                            and point.source_id = snapshot.source_id
                                            and (member.finalized_at is null or point.is_final)
                                        order by
                                            (point.cutoff_at
                                                at time zone coalesce(fight.time_zone, 'UTC')
                                            )::date,
                                            point.cutoff_at desc,
                                            point.created_at desc,
                                            point.id desc
                                    ) as scored
                                ) as points
                            )
                        end as step_checkpoints
                    from private.fight_score_snapshots as snapshot
                    join public.fights as fight on fight.id = snapshot.fight_id
                    where snapshot.fight_id = member.fight_id and snapshot.user_id = member.user_id
                        and snapshot.source_id = member.selected_source_id
                        and (member.finalized_at is null or snapshot.is_final)
                    order by snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
                    limit 1
                ) as history on member.state = 'accepted'
                where member.fight_id in (select id from visible_fights)
            ), visible_profiles as (
                select user_id, handle, display_name, avatar_media_id, companion_id
                from public.profiles
                where user_id in (
                    select user_id from visible_members union select owner_id from visible_fights
                )
            ), visible_series as (
                select id, join_code, visibility, recurring, suggested
                from public.fight_series
                where id in (select series_id from visible_fights)
            ), chart_bounds as (
                select min((starts_at at time zone ${timeZone})::date) as first_day,
                    max(least(
                        ((ends_at - interval '1 microsecond') at time zone ${timeZone})::date,
                        (starts_at at time zone ${timeZone})::date + 40
                    )) as last_day
                from visible_fights
            ), visible_days as (
                select user_id, day, steps
                from public.step_days
                where user_id in (select user_id from visible_members)
                    and day between (select first_day from chart_bounds) and (select last_day from chart_bounds)
            )
            select jsonb_build_object(
                'fights', coalesce((select jsonb_agg(to_jsonb(f) order by starts_at, id) from visible_fights f), '[]'::jsonb),
                'members', coalesce((select jsonb_agg(to_jsonb(m) order by fight_id, user_id) from visible_members m), '[]'::jsonb),
                'profiles', coalesce((select jsonb_agg(to_jsonb(p) order by user_id) from visible_profiles p), '[]'::jsonb),
                'series', coalesce((select jsonb_agg(to_jsonb(s) order by id) from visible_series s), '[]'::jsonb),
                'step_days', coalesce((select jsonb_agg(to_jsonb(d) order by day, user_id) from visible_days d), '[]'::jsonb)
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
    }));
}
