import { z } from "zod";
import {
    blockFeedAuthorRequestSchema,
    blockFeedAuthorResponseSchema,
    reportFightPostRequestSchema,
    reportFightPostResponseSchema,
} from "@/lib/types/feed/fight-post";
import { mediaObjectSchema } from "@/lib/types/media/media";

export const feedbackKindValues = ["bug", "feature"] as const;
export const feedbackKindSchema = z.enum(feedbackKindValues);

export const feedbackStatusValues = ["open", "archived"] as const;
export const feedbackStatusSchema = z.enum(feedbackStatusValues);
export const feedbackSortValues = ["votes", "newest", "oldest"] as const;
export const feedbackSortSchema = z.enum(feedbackSortValues);

export const feedbackArchiveRequestSchema = z.object({
    archived: z.boolean(),
    reason: z.string().trim().max(280).optional(),
}).strict();

export const feedbackArchiveResponseSchema = z.object({
    archived: z.boolean(),
    archive_reason: z.string().nullable(),
}).strict();

export const feedbackOwnerRowSchema = z.object({ author_id: z.string().uuid() });

const feedbackMetadataTextSchema = z.string().trim().min(1).max(120);

export const feedbackMetadataSchema = z
    .object({
        app_version: feedbackMetadataTextSchema.optional(),
        app_build: feedbackMetadataTextSchema.optional(),
        backend: feedbackMetadataTextSchema.optional(),
        bundle_id: feedbackMetadataTextSchema.optional(),
        language: z.string().trim().min(1).max(32).optional(),
        preferred_languages: z
            .array(z.string().trim().min(1).max(32))
            .max(8)
            .optional(),
        locale: z.string().trim().min(1).max(64).optional(),
        region: z.string().trim().min(1).max(32).optional(),
        time_zone: z.string().trim().min(1).max(80).optional(),
        calendar: z.string().trim().min(1).max(64).optional(),
        hour_cycle: z.string().trim().min(1).max(8).optional(),
        measurement_system: z.string().trim().min(1).max(16).optional(),
        os: z.string().trim().min(1).max(32).optional(),
        os_version: z.string().trim().min(1).max(32).optional(),
        device_model: z.string().trim().min(1).max(64).optional(),
        idiom: z.string().trim().min(1).max(16).optional(),
        look: z.string().trim().min(1).max(16).optional(),
        appearance: z.string().trim().min(1).max(16).optional(),
        layout_direction: z.string().trim().min(1).max(16).optional(),
        content_size: z.string().trim().min(1).max(64).optional(),
        reduce_motion: z.boolean().optional(),
        bold_text: z.boolean().optional(),
        increase_contrast: z.boolean().optional(),
        voice_over: z.boolean().optional(),
        low_power_mode: z.boolean().optional(),
        thermal_state: z.string().trim().min(1).max(32).optional(),
        background_refresh: z.string().trim().min(1).max(32).optional(),
        screen_scale: z.number().finite().min(0).max(16).optional(),
        screen_width: z.number().finite().min(0).max(10_000).optional(),
        screen_height: z.number().finite().min(0).max(10_000).optional(),
    })
    .passthrough()
    .refine(
        (value) => JSON.stringify(value).length <= 8192,
        "metadata is too large",
    );

export const createFeedbackPostRequestSchema = z
    .object({
        kind: feedbackKindSchema,
        title: z.string().trim().min(1).max(80),
        body: z.string().trim().min(1).max(2000),
        media_ids: z.array(z.string().uuid()).max(8).default([]),
        metadata: feedbackMetadataSchema.optional(),
    })
    .strict();

export const createFeedbackCommentRequestSchema = z
    .object({
        body: z.string().trim().min(2).max(500),
        metadata: feedbackMetadataSchema.optional(),
    })
    .strict();

export const listFeedbackQuerySchema = z
    .object({
        kind: feedbackKindSchema.optional(),
        status: feedbackStatusSchema.optional(),
        sort: feedbackSortSchema.optional(),
    })
    .strict();

export const reportFeedbackPostRequestSchema = reportFightPostRequestSchema;

export const reportFeedbackPostResponseSchema = reportFightPostResponseSchema;

export const blockFeedbackAuthorRequestSchema = blockFeedAuthorRequestSchema;

export const blockFeedbackAuthorResponseSchema = blockFeedAuthorResponseSchema;

export const feedbackPostSummarySchema = z
    .object({
        id: z.string().uuid(),
        kind: feedbackKindSchema,
        title: z.string(),
        body: z.string(),
        vote_count: z.number().int(),
        comment_count: z.number().int(),
        voted: z.boolean(),
        author_id: z.string().uuid(),
        author_handle: z.string(),
        mine: z.boolean(),
        created_at: z.string().datetime(),
        metadata: feedbackMetadataSchema,
        media: z.array(mediaObjectSchema).default([]),
        archived: z.boolean().default(false),
        archive_reason: z.string().nullable().default(null),
    })
    .strict();

export const feedbackCommentSchema = z
    .object({
        id: z.string().uuid(),
        author_id: z.string().uuid().optional(),
        body: z.string(),
        author_handle: z.string(),
        created_at: z.string().datetime(),
        metadata: feedbackMetadataSchema,
    })
    .strict();

export const feedbackPostRowSchema = feedbackPostSummarySchema.omit({ media: true }).extend({
    created_at: z.union([z.date(), z.string().datetime()]),
    metadata: z.unknown(),
});

export const feedbackCommentRowSchema = feedbackCommentSchema.extend({
    created_at: z.union([z.date(), z.string().datetime()]),
    metadata: z.unknown(),
});

export const feedbackListResponseSchema = z
    .object({
        posts: z.array(feedbackPostSummarySchema),
        can_archive: z.boolean().optional(),
    })
    .strict();

export const feedbackPostResponseSchema = z
    .object({
        post: feedbackPostSummarySchema,
    })
    .strict();

export const feedbackPostDetailSchema = z
    .object({
        post: feedbackPostSummarySchema,
        comments: z.array(feedbackCommentSchema),
    })
    .strict();

export const feedbackDetailResponseSchema = feedbackPostDetailSchema
    .extend({
        can_launch_fix: z.boolean(),
        can_delete: z.boolean().default(false),
        can_archive: z.boolean().default(false),
    })
    .strict();

export const launchFeedbackFixRequestSchema = z
    .object({
        metadata: feedbackMetadataSchema.optional(),
    })
    .strict();

export const feedbackFixAgentResponseSchema = z
    .object({
        agent_id: z.string().min(1),
        agent_url: z.string().url(),
    })
    .strict();

export const feedbackVoteResponseSchema = z
    .object({
        voted: z.boolean(),
        vote_count: z.number().int(),
    })
    .strict();

export const feedbackCommentResponseSchema = z
    .object({
        comment: feedbackCommentSchema,
    })
    .strict();

export type FeedbackKind = z.infer<typeof feedbackKindSchema>;
export type FeedbackStatus = z.infer<typeof feedbackStatusSchema>;
export type FeedbackSort = z.infer<typeof feedbackSortSchema>;
export type FeedbackArchiveRequest = z.infer<typeof feedbackArchiveRequestSchema>;
export type FeedbackArchiveResponse = z.infer<typeof feedbackArchiveResponseSchema>;
export type FeedbackOwnerRow = z.infer<typeof feedbackOwnerRowSchema>;
export type FeedbackPostRow = z.infer<typeof feedbackPostRowSchema>;
export type FeedbackCommentRow = z.infer<typeof feedbackCommentRowSchema>;
export type FeedbackMetadata = z.infer<typeof feedbackMetadataSchema>;
export type ReportFeedbackPostRequest = z.infer<
    typeof reportFeedbackPostRequestSchema
>;
export type ReportFeedbackPostResponse = z.infer<
    typeof reportFeedbackPostResponseSchema
>;
export type BlockFeedbackAuthorRequest = z.infer<
    typeof blockFeedbackAuthorRequestSchema
>;
export type BlockFeedbackAuthorResponse = z.infer<
    typeof blockFeedbackAuthorResponseSchema
>;
export type CreateFeedbackPostRequest = z.infer<
    typeof createFeedbackPostRequestSchema
>;
export type CreateFeedbackCommentRequest = z.infer<
    typeof createFeedbackCommentRequestSchema
>;
export type ListFeedbackQuery = z.infer<typeof listFeedbackQuerySchema>;
export type FeedbackPostSummary = z.infer<typeof feedbackPostSummarySchema>;
export type FeedbackComment = z.infer<typeof feedbackCommentSchema>;
export type FeedbackListResponse = z.infer<typeof feedbackListResponseSchema>;
export type FeedbackPostResponse = z.infer<typeof feedbackPostResponseSchema>;
export type FeedbackPostDetail = z.infer<typeof feedbackPostDetailSchema>;
export type FeedbackDetailResponse = z.infer<
    typeof feedbackDetailResponseSchema
>;
export type LaunchFeedbackFixRequest = z.infer<
    typeof launchFeedbackFixRequestSchema
>;
export type FeedbackFixAgentResponse = z.infer<
    typeof feedbackFixAgentResponseSchema
>;
export type FeedbackVoteResponse = z.infer<typeof feedbackVoteResponseSchema>;
export type FeedbackCommentResponse = z.infer<
    typeof feedbackCommentResponseSchema
>;
