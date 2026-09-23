import { z } from "zod";

export const notificationPreferenceKeyValues = [
    "enabled",
    "fight_invite",
    "ending_24h",
    "ending_week",
    "fight_ended",
    "final_sync",
    "fight_finalized",
    "mention",
    "feed_post",
    "post_comment",
    "comment_reply",
    "post_reaction",
    "challenge_reminder",
    "daily_status",
] as const;

export const notificationPreferencesSchema = z.object({
    enabled: z.boolean(),
    fight_invite: z.boolean(),
    ending_24h: z.boolean(),
    ending_week: z.boolean(),
    fight_ended: z.boolean(),
    final_sync: z.boolean(),
    fight_finalized: z.boolean(),
    mention: z.boolean(),
    feed_post: z.boolean(),
    post_comment: z.boolean(),
    comment_reply: z.boolean(),
    post_reaction: z.boolean(),
    challenge_reminder: z.boolean(),
    daily_status: z.boolean(),
});

export const updateNotificationPreferencesRequestSchema =
    notificationPreferencesSchema
        .partial()
        .strict()
        .refine(
            (input) => Object.keys(input).length > 0,
            {
                message: "Supply at least one notification setting",
            },
        );

export const defaultNotificationPreferences: NotificationPreferences = {
    enabled: true,
    fight_invite: true,
    ending_24h: true,
    ending_week: false,
    fight_ended: false,
    final_sync: true,
    fight_finalized: true,
    mention: true,
    feed_post: false,
    post_comment: true,
    comment_reply: true,
    post_reaction: true,
    challenge_reminder: true,
    daily_status: false,
};

export type NotificationPreferenceKey =
    (typeof notificationPreferenceKeyValues)[number];
export type NotificationPreferences = z.infer<
    typeof notificationPreferencesSchema
>;
export type UpdateNotificationPreferencesRequest = z.infer<
    typeof updateNotificationPreferencesRequestSchema
>;
