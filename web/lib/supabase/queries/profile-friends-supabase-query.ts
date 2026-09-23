import type { Sql } from "postgres";
import { randomUUID } from "node:crypto";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { profileFriendListRowSchema, friendshipRowSchema, type FriendsPage, type FriendsQuery, type FriendshipAction, type FriendshipResponse } from "@/lib/types/friends/friendship";
import { profileFeatureConfigSchema } from "@/lib/types/profiles/shared-profile";
import { signMediaUrl } from "./media-supabase-query";
import { loadProfileAccess } from "./shared-profiles-supabase-query";

/** A reverse request stays pending until its recipient explicitly accepts it. */
export async function changeFriendship(viewerId: string, targetId: string, action: FriendshipAction, database: Sql = createDatabaseClient()): Promise<FriendshipResponse> {
    if (viewerId === targetId) throw new ApiError(400, "validation", "Choose another person");
    return database.begin(async (sql) => {
        await loadProfileAccess(sql, viewerId, targetId, true);
        const [low, high] = [viewerId.toLowerCase(), targetId.toLowerCase()].sort();
        const rows = await sql`select requester_id, state from private.profile_friendships where user_low = ${low} and user_high = ${high}`;
        const existing = rows[0] ? friendshipRowSchema.parse(rows[0]) : null;
        let event: "friend_request" | "friend_accept" | null = null;
        let state: FriendshipResponse["friendship"] = existing?.state === "accepted" ? "friends"
            : existing ? existing.requester_id === viewerId ? "outgoing" : "incoming" : "none";
        if (action === "request" && !existing) {
            await sql`insert into private.profile_friendships(user_low, user_high, requester_id) values (${low}, ${high}, ${viewerId})`;
            state = "outgoing";
            event = "friend_request";
        } else if (action === "accept") {
            if (!existing) throw new ApiError(409, "conflict", "That friend request is no longer available");
            if (existing.state !== "accepted") {
                if (existing.requester_id === viewerId) throw new ApiError(403, "forbidden", "Only the recipient can accept a friend request");
                await sql`update private.profile_friendships set state = 'accepted', accepted_at = now() where user_low = ${low} and user_high = ${high}`;
                event = "friend_accept";
                state = "friends";
            }
        } else if (action === "decline" || action === "remove") {
            if (action === "decline" && existing && (existing.requester_id === viewerId || existing.state === "accepted")) {
                throw new ApiError(403, "forbidden", "Only the recipient can decline a pending request");
            }
            await sql`delete from private.profile_friendships where user_low = ${low} and user_high = ${high}`;
            await sql`update private.rivalry_artworks set hidden = true, state = 'cancelled' where user_low = ${low} and user_high = ${high}`;
            state = "none";
        }
        if (event && profileFeatureConfigSchema.parse({ measurement: process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED }).measurement) {
            await sql`
                insert into private.profile_events(actor_id, event_id, target_id, kind, attributed_source)
                values (${viewerId}, ${randomUUID()}, ${targetId}, ${event}, (
                    select source from private.profile_events where actor_id = ${viewerId} and target_id = ${targetId}
                        and kind = 'view' and created_at > now() - interval '7 days' order by created_at desc limit 1
                ))
            `;
        }
        return { friendship: state };
    });
}

export async function listProfileFriends(userId: string, query: FriendsQuery, database: Sql = createDatabaseClient()): Promise<FriendsPage> {
    return database.begin(async (sql) => {
        await sql`select id as user_id from public.profiles where id = ${userId} and deleted_at is null for share`;
        const rows = profileFriendListRowSchema.array().parse(await sql`
            select profile.id as user_id, profile.handle, profile.display_name, profile.companion_id, case when profile.companion_id = 'custom' then profile.companion_image_url end avatar_url,
                friendship.state, friendship.requester_id, media.object_path avatar_path
            from private.profile_friendships friendship
            join public.profiles profile on profile.id = case when friendship.user_low = ${userId}
                then friendship.user_high else friendship.user_low end
            left join public.media_objects media on media.id = profile.avatar_media_id and media.status = 'ready'
            where (friendship.user_low = ${userId} or friendship.user_high = ${userId})
                and profile.deleted_at is null
                and not exists (
                    select 1 from (
                        select blocker_id, blocked_id from private.profile_blocks
                        union all select blocker_id, blocked_id from private.feed_blocks
                        union all select blocker_id, blocked_id from private.feedback_blocks
                    ) blocks where (blocker_id = ${userId} and blocked_id = profile.id)
                        or (blocker_id = profile.id and blocked_id = ${userId})
                )
            order by profile.id
        `);
        const filtered = rows.filter((row) => query.kind === "accepted" ? row.state === "accepted"
            : row.state === "pending" && (query.kind === "outgoing" ? row.requester_id === userId : row.requester_id !== userId));
        const afterCursor = filtered.filter((row) => !query.cursor || row.user_id > query.cursor);
        const people = await Promise.all(afterCursor.slice(0, query.limit).map(async (row) => ({
            user_id: row.user_id, handle: row.handle, display_name: row.display_name, companion_id: row.companion_id,
            avatar_url: row.avatar_url ?? (row.avatar_path ? await signMediaUrl(row.avatar_path) : null),
        })));
        return {
            people,
            next_cursor: afterCursor.length > query.limit ? people[people.length - 1].user_id : null,
            incoming_count: rows.filter((row) => row.state === "pending" && row.requester_id !== userId).length,
        };
    });
}

/** Existing Feed/Feedback hiding also revokes new Profile permissions. */
export async function blockProfile(userId: string, targetId: string, database: Sql = createDatabaseClient()): Promise<{ blocked: boolean }> {
    if (userId === targetId) throw new ApiError(400, "validation", "You cannot block yourself");
    return database.begin(async (sql) => {
        const profiles = await sql`select id as user_id from public.profiles where id in (${userId}, ${targetId}) and deleted_at is null order by user_id for update`;
        if (profiles.length !== 2) throw new ApiError(404, "not_found", "Profile unavailable");
        await sql`insert into private.profile_blocks(blocker_id, blocked_id) values (${userId}, ${targetId}) on conflict do nothing`;
        await sql`insert into private.feed_blocks(blocker_id, blocked_id) values (${userId}, ${targetId}) on conflict do nothing`;
        await sql`insert into private.feedback_blocks(blocker_id, blocked_id) values (${userId}, ${targetId}) on conflict do nothing`;
        const [low, high] = [userId.toLowerCase(), targetId.toLowerCase()].sort();
        await sql`delete from private.profile_friendships where user_low = ${low} and user_high = ${high}`;
        await sql`update private.rivalry_artworks set hidden = true, state = 'cancelled' where user_low = ${low} and user_high = ${high}`;
        return { blocked: true };
    });
}

export async function reportProfile(userId: string, targetId: string, reason: string, database: Sql = createDatabaseClient()): Promise<{ reported: boolean }> {
    if (userId === targetId) throw new ApiError(400, "validation", "You cannot report yourself");
    return database.begin(async (sql) => {
        await loadProfileAccess(sql, userId, targetId, true);
        await sql`insert into private.profile_reports(reporter_id, target_id, reason) values (${userId}, ${targetId}, ${reason})
            on conflict (reporter_id, target_id) do update set reason = excluded.reason, created_at = now()`;
        return { reported: true };
    });
}
