import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    profileSearchSchema,
    type ProfileSearch,
} from "@/lib/types/profiles/profile-search";

/**
 * Up to 8 people whose username starts with `query`, exact match first. Never the caller, deleted
 * accounts, or anyone either side blocked.
 */
export async function searchProfiles(
    userId: string,
    query: string,
    database: Sql = createDatabaseClient(),
): Promise<ProfileSearch> {
    // NOTE: unlike exact lookup this has no hourly cap. Usernames already show in shared fights; add one if scraping appears.
    const people = profileSearchSchema.shape.people.parse(await database`
        select profile.id as user_id, profile.handle, profile.display_name, profile.companion_id,
            case when profile.companion_id = 'custom' then profile.companion_image_url end as avatar_url
        from public.profiles as profile
        where starts_with(lower(profile.handle), ${query})
            and profile.id <> ${userId}
            and profile.deleted_at is null
            and not exists (
                select 1 from (
                    select blocker_id, blocked_id from private.profile_blocks
                    union all select blocker_id, blocked_id from private.feed_blocks
                    union all select blocker_id, blocked_id from private.feedback_blocks
                ) as blocks where (blocker_id = ${userId} and blocked_id = profile.id)
                    or (blocker_id = profile.id and blocked_id = ${userId})
            )
        order by lower(profile.handle) = ${query} desc, length(profile.handle), lower(profile.handle)
        limit 8
    `);
    return { people };
}
