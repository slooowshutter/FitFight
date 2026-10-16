import { z } from "zod";
import { pendingNotificationIntentSchema } from "./notification-intent";
import { notificationPreferencesSchema } from "./notification-preferences";

export const notificationDeliveryRowSchema = pendingNotificationIntentSchema.extend({
    expires_at: z.coerce.date(),
    alert_body: z.string().nullable(),
    fight_state: z.string().nullable(),
    fight_host_id: z.string().uuid().nullable(),
    fight_friends: z.boolean().nullable(),
    fight_name: z.string(),
    owner_handle: z.string().nullable(),
    ends_at: z.coerce.date(),
    sync_deadline: z.coerce.date().nullable(),
    time_zone: z.string(),
    member_state: z.string().nullable(),
    final_steps_complete: z.boolean().nullable(),
    preferences: notificationPreferencesSchema.partial().nullable(),
});
export const notificationPostContextSchema = z.object({
    kind: z.string(),
    post_id: z.string().uuid(),
    comment_id: z.string().uuid().nullable(),
    fight_id: z.string().uuid(),
    actor_handle: z.string(),
    body: z.string(),
    post_body: z.string(),
    fight_name: z.string(),
    media_path: z.string().nullable(),
});
export const notificationContentSchema = z.object({
    title: z.string(),
    body: z.string(),
    route: z.string(),
    threadId: z.string(),
    imageUrl: z.string().url().nullable(),
});
export const friendsResultsCountsSchema = z.object({
    month: z.string().regex(/^\d{4}-\d{2}$/),
    won: z.number().int().nonnegative(),
    total: z.number().int().positive(),
});
export const notificationRecipientRowSchema = z.object({
    user_id: z.string().uuid(),
    locale: z.string().nullable(),
    enabled: z.boolean().nullable(),
    mention: z.boolean().nullable(),
    feed_post: z.boolean().nullable(),
    post_comment: z.boolean().nullable(),
    comment_reply: z.boolean().nullable(),
    post_reaction: z.boolean().nullable(),
});
export type NotificationRecipientRow = z.infer<typeof notificationRecipientRowSchema>;
export type NotificationDeliveryRow = z.infer<typeof notificationDeliveryRowSchema>;
export type NotificationPostContext = z.infer<typeof notificationPostContextSchema>;
export type NotificationContent = z.infer<typeof notificationContentSchema>;
export type FriendsResultsCounts = z.infer<typeof friendsResultsCountsSchema>;
