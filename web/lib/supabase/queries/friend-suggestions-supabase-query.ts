import type { Sql } from "postgres";
import { APP_WIDE_JOIN_CODE } from "@/lib/domain/fights/join-code";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    friendSuggestionSchema,
    type FriendSuggestions,
} from "@/lib/types/friends/friend-suggestion";

/**
 * People the caller raced or sat out with who are not friends, requested, blocked, or deleted. A repeating
 * Fight counts only while both are still in its series; automatic Fights (app-wide, suggested, founder,
 * friend) never count.
 */
export async function listFriendSuggestions(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<FriendSuggestions> {
    const people = friendSuggestionSchema.array().parse(await database`
        select profile.id as user_id, profile.handle, profile.display_name, profile.companion_id,
            case when profile.companion_id = 'custom' then profile.companion_image_url end as avatar_url,
            shared.shared_fights
        from (
            select theirs.user_id, count(*)::int as shared_fights, max(fight.starts_at) as last_shared_at
            from public.fight_members as mine
            join public.fight_members as theirs on theirs.fight_id = mine.fight_id and theirs.user_id <> mine.user_id
            join public.fights as fight on fight.id = mine.fight_id
            left join public.fight_series as series on series.id = fight.series_id
            where mine.user_id = ${userId} and fight.host_id is null and not fight.friends
                and coalesce(series.join_code, '') <> ${APP_WIDE_JOIN_CODE} and not coalesce(series.suggested, false)
                and mine.state in ('accepted', 'deferred') and theirs.state in ('accepted', 'deferred')
                and (fight.series_id is null or exists (
                    select 1 from public.fight_series_members as my_series
                    join public.fight_series_members as their_series on their_series.series_id = my_series.series_id
                    where my_series.series_id = fight.series_id
                        and my_series.user_id = ${userId} and their_series.user_id = theirs.user_id
                        and my_series.state in ('accepted', 'deferred') and their_series.state in ('accepted', 'deferred')
                ))
            group by theirs.user_id
        ) as shared
        join public.profiles as profile on profile.id = shared.user_id
        where profile.deleted_at is null
            and not exists (
                select 1 from private.profile_friendships as friendship
                where (friendship.user_low = ${userId} and friendship.user_high = profile.id)
                    or (friendship.user_low = profile.id and friendship.user_high = ${userId})
            )
            and not exists (
                select 1 from (
                    select blocker_id, blocked_id from private.profile_blocks
                    union all select blocker_id, blocked_id from private.feed_blocks
                    union all select blocker_id, blocked_id from private.feedback_blocks
                ) as blocks where (blocker_id = ${userId} and blocked_id = profile.id)
                    or (blocker_id = profile.id and blocked_id = ${userId})
            )
        order by shared.shared_fights desc, shared.last_shared_at desc, profile.id
        limit 10
    `);
    return { people };
}
