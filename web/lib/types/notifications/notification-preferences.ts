import { z } from "zod";

export const notificationPreferenceKeyValues = [
  "feed_post",
  "post_comment",
  "comment_reply",
  "post_reaction",
  "challenge_reminder",
  "daily_status",
] as const;

export const notificationPreferencesSchema = z.object({
  feed_post: z.boolean(),
  post_comment: z.boolean(),
  comment_reply: z.boolean(),
  post_reaction: z.boolean(),
  challenge_reminder: z.boolean(),
  daily_status: z.boolean(),
});

export const updateNotificationPreferencesRequestSchema = notificationPreferencesSchema
  .partial()
  .strict()
  .refine((input) => (
    input.feed_post !== undefined
    || input.post_comment !== undefined
    || input.comment_reply !== undefined
    || input.post_reaction !== undefined
    || input.challenge_reminder !== undefined
    || input.daily_status !== undefined
  ), {
    message: "Supply at least one notification setting",
  });

export const defaultNotificationPreferences: NotificationPreferences = {
  feed_post: true,
  post_comment: true,
  comment_reply: true,
  post_reaction: true,
  challenge_reminder: true,
  daily_status: true,
};

export type NotificationPreferenceKey = (typeof notificationPreferenceKeyValues)[number];
export type NotificationPreferences = z.infer<typeof notificationPreferencesSchema>;
export type UpdateNotificationPreferencesRequest = z.infer<
  typeof updateNotificationPreferencesRequestSchema
>;
