import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  defaultNotificationPreferences,
  notificationPreferencesSchema,
  type NotificationPreferences,
  type UpdateNotificationPreferencesRequest,
} from "@/lib/types/notifications/notification-preferences";

type PreferenceRow = {
  feed_post: boolean;
  post_comment: boolean;
  comment_reply: boolean;
  post_reaction: boolean;
  challenge_reminder: boolean;
  daily_status: boolean;
};

export async function readNotificationPreferences(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<NotificationPreferences> {
  const [row] = await database<PreferenceRow[]>`
    select feed_post, post_comment, comment_reply, post_reaction, challenge_reminder, daily_status
    from private.notification_preferences
    where user_id = ${userId}
  `;
  if (!row) return defaultNotificationPreferences;
  return notificationPreferencesSchema.parse(row);
}

export async function updateNotificationPreferences(
  userId: string,
  input: UpdateNotificationPreferencesRequest,
  database: Sql = createDatabaseClient(),
): Promise<NotificationPreferences> {
  const current = await readNotificationPreferences(userId, database);
  const next = notificationPreferencesSchema.parse({ ...current, ...input });
  const [row] = await database<PreferenceRow[]>`
    insert into private.notification_preferences (
      user_id, feed_post, post_comment, comment_reply, post_reaction, challenge_reminder, daily_status
    ) values (
      ${userId},
      ${next.feed_post},
      ${next.post_comment},
      ${next.comment_reply},
      ${next.post_reaction},
      ${next.challenge_reminder},
      ${next.daily_status}
    )
    on conflict (user_id) do update set
      feed_post = excluded.feed_post,
      post_comment = excluded.post_comment,
      comment_reply = excluded.comment_reply,
      post_reaction = excluded.post_reaction,
      challenge_reminder = excluded.challenge_reminder,
      daily_status = excluded.daily_status,
      updated_at = now()
    returning feed_post, post_comment, comment_reply, post_reaction, challenge_reminder, daily_status
  `;
  return notificationPreferencesSchema.parse(row ?? next);
}
