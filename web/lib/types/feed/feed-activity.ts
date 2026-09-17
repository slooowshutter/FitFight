import { z } from "zod";

export const feedActivityKindValues = [
    "feed_post", "post_comment", "comment_reply", "post_reaction",
    "invited", "accepted", "deferred", "declined", "withdrawn", "disqualified",
] as const;
export const feedActivityKindSchema = z.enum(feedActivityKindValues);

export const feedActivityPersonSchema = z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
});

export const feedActivityItemSchema = z.object({
    id: z.string(),
    kind: feedActivityKindSchema,
    occurred_at: z.string().datetime({ offset: true }).nullable(),
    actor: feedActivityPersonSchema,
    subject: feedActivityPersonSchema.nullable(),
    fight_id: z.string().uuid(),
    fight_name: z.string(),
    post_id: z.string().uuid().nullable(),
    comment_id: z.string().uuid().nullable(),
    body: z.string(),
});

export const feedActivityCursorSchema = z.object({
    at: z.string().datetime({ offset: true }).nullable(),
    id: z.string().regex(/^(membership|post|comment|reaction):[a-f0-9:-]+$/),
});

export const listFeedActivityQuerySchema = z.object({
    limit: z.coerce.number().int().min(1).max(80).default(40),
    cursor: z.string().max(220).transform((value, context) => {
        const [at, id] = value.split("|");
        const parsed = feedActivityCursorSchema.safeParse({
            at: at === "unknown" ? null : at,
            id,
        });
        if (!parsed.success || value.split("|").length !== 2) {
            context.addIssue({ code: z.ZodIssueCode.custom, message: "Invalid activity cursor" });
            return z.NEVER;
        }
        return parsed.data;
    }).optional(),
});

export const feedActivityResponseSchema = z.object({
    events: z.array(feedActivityItemSchema),
    next_cursor: z.string().nullable(),
});

export type FeedActivityKind = z.infer<typeof feedActivityKindSchema>;
export type FeedActivityPerson = z.infer<typeof feedActivityPersonSchema>;
export type FeedActivityItem = z.infer<typeof feedActivityItemSchema>;
export type FeedActivityCursor = z.infer<typeof feedActivityCursorSchema>;
export type ListFeedActivityQuery = z.infer<typeof listFeedActivityQuerySchema>;
export type FeedActivityResponse = z.infer<typeof feedActivityResponseSchema>;
