import type { Sql } from "postgres";
import { profileAccess } from "@/lib/domain/profiles/profile-access";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { profileFeatureConfigSchema, type ProfileViewRequest } from "@/lib/types/profiles/shared-profile";
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
        if (count.n >= 60) throw new ApiError(429, "rate_limited", "Too many profile opens");
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
        const events = await sql`delete from private.profile_events where created_at < now() - interval '30 days' returning event_id`;
        const lookups = await sql`delete from private.profile_lookup_attempts where created_at < now() - interval '1 hour' returning id`;
        return { events_deleted: events.length, lookup_attempts_deleted: lookups.length };
    });
}
