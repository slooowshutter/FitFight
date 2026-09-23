import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    defaultNotificationPreferences,
    notificationPreferencesSchema,
    type NotificationPreferences,
    type UpdateNotificationPreferencesRequest,
} from "@/lib/types/notifications/notification-preferences";

export async function readNotificationPreferences(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<NotificationPreferences> {
    const [row] = await database`
        select enabled, fight_invite, ending_24h, ending_week, fight_ended,
            final_sync, fight_finalized, mention, feed_post, post_comment,
            comment_reply, post_reaction, challenge_reminder, daily_status
        from private.notification_preferences
        where user_id = ${userId}
    `;
    return row ? notificationPreferencesSchema.parse(row) : defaultNotificationPreferences;
}

/** Partial writes preserve other switches, including edits made on another device. */
export async function updateNotificationPreferences(
    userId: string,
    input: UpdateNotificationPreferencesRequest,
    database: Sql = createDatabaseClient(),
): Promise<NotificationPreferences> {
    const changes = { ...input };
    if (input.challenge_reminder !== undefined) {
        changes.fight_ended ??= input.challenge_reminder;
        changes.final_sync ??= input.challenge_reminder;
        changes.fight_finalized ??= input.challenge_reminder;
    }
    const [row] = await database`
        insert into private.notification_preferences ${database({ user_id: userId, ...changes })}
        on conflict (user_id) do update set ${database(changes)}
        returning enabled, fight_invite, ending_24h, ending_week, fight_ended,
            final_sync, fight_finalized, mention, feed_post, post_comment,
            comment_reply, post_reaction, challenge_reminder, daily_status
    `;
    return notificationPreferencesSchema.parse(row);
}
