import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { recentSyncsSchema, type RecentSyncs } from "@/lib/types/admin/recent-syncs";

/** Accounts whose Apple Health upload reached this database in the last 7 days, newest first. */
export async function readRecentSyncs(
    database: Sql = createDatabaseClient(),
): Promise<RecentSyncs> {
    const people = await database`
        select profile.user_id, profile.handle, profile.display_name,
            to_char(max(source.last_success_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as last_synced_at
        from public.data_sources as source
        join public.profiles as profile on profile.user_id = source.user_id
        where source.provider = 'apple_health'
            and source.last_success_at >= now() - interval '7 days'
            and profile.deleted_at is null
        group by profile.user_id
        order by max(source.last_success_at) desc
    `;
    return recentSyncsSchema.parse({ people });
}
