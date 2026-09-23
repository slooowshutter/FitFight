import { z } from "zod";
import { pendingNotificationIntentSchema } from "./notification-intent";
import { notificationPreferencesSchema } from "./notification-preferences";

export const notificationDeliveryRowSchema = pendingNotificationIntentSchema.extend({
    expires_at: z.coerce.date(),
    alert_body: z.string().nullable(),
    fight_state: z.string().nullable(),
    fight_name: z.string(),
    owner_handle: z.string().nullable(),
    ends_at: z.coerce.date(),
    sync_deadline: z.coerce.date(),
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
