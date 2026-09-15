import { z } from "zod";

export const transferTableValues = [
    "auth.users",
    "auth.identities",
    "public.profiles",
    "public.data_sources",
    "public.media_objects",
    "public.fight_series",
    "public.fights",
    "public.fight_series_members",
    "public.fight_members",
    "public.fight_invites",
    "public.step_days",
    "public.metric_days",
    "private.healthkit_activity_days",
    "private.healthkit_workouts",
    "private.fight_score_snapshots",
    "private.referrals",
    "public.friendships",
    "public.fight_posts",
    "public.fight_post_channels",
    "public.fight_post_media",
    "public.fight_post_tags",
    "public.fight_post_reactions",
    "public.fight_post_comments",
    "private.fight_post_reports",
    "private.fight_post_comment_reports",
    "private.feed_blocks",
    "public.feedback_posts",
    "public.feedback_post_media",
    "public.feedback_comments",
    "public.feedback_votes",
    "private.feedback_post_reports",
    "private.feedback_blocks",
    "private.notification_preferences",
] as const;

export const transferTableSchema = z.enum(transferTableValues);
export const transferUserColumnValues = [
    "id",
    "aud",
    "role",
    "email",
    "email_confirmed_at",
    "raw_app_meta_data",
    "raw_user_meta_data",
    "created_at",
    "updated_at",
    "is_sso_user",
    "is_anonymous",
    "banned_until",
    "deleted_at",
] as const;
export const transferRowSchema = z.record(z.unknown());
export const transferProfilePolicyValues = ["beta", "production"] as const;
export const transferProfilePolicySchema = z.enum(transferProfilePolicyValues);

export const transferTableDefinitionSchema = z.object({
    columns: z.string().array().min(1),
    primary_key: z.string().array().min(1),
    user_columns: z.string().array(),
    source_columns: z.string().array(),
});

export const transferForeignKeySchema = z.object({
    child: z.string().min(1),
    parent: z.string().min(1),
    child_columns: z.string().array().min(1),
    parent_columns: z.string().array().min(1),
    match_kind: z.literal("s"),
});

export const transferSnapshotSchema = z
    .object({
        captured_at: z.string().datetime({ offset: true }),
        project_ref: z.string().regex(/^[a-z]{20}$/),
        definitions: z.record(transferTableDefinitionSchema),
        rows: z.record(transferRowSchema.array()),
        pending_media: z.number().int().nonnegative(),
    })
    .superRefine((snapshot, context) => {
        for (const table of transferTableValues) {
            if (!snapshot.definitions[table] || !snapshot.rows[table]) {
                context.addIssue({
                    code: "custom",
                    message: "Incomplete transfer snapshot",
                    path: [table],
                });
            }
        }
    });

export const transferUserSchema = z
    .object({
        id: z.string().uuid(),
        email: z.string().nullable(),
        deleted_at: z.string().nullable(),
    })
    .passthrough();

export const transferIdentitySchema = z
    .object({
        id: z.string().uuid(),
        user_id: z.string().uuid(),
        provider: z.literal("apple"),
        provider_id: z.string().min(1),
    })
    .passthrough();

export const transferProfileSchema = z
    .object({
        user_id: z.string().uuid(),
        handle: z.string(),
        referral_code: z.string(),
        deleted_at: z.string().nullable(),
    })
    .passthrough();

export const transferSourceSchema = z
    .object({
        id: z.string().uuid(),
        user_id: z.string().uuid(),
        provider: z.string(),
        connection_route: z.string(),
        last_success_at: z.string().nullable(),
        revoked_at: z.string().nullable(),
    })
    .passthrough();

export const transferMediaSchema = z
    .object({
        id: z.string().uuid(),
        owner_id: z.string().uuid(),
        status: z.literal("ready"),
        bucket_id: z.literal("user-media"),
        purpose: z.enum(["profile", "fight_post", "feedback"]),
        object_path: z.string().min(1),
        byte_size: z.coerce.number().int().positive().max(52_428_800),
        content_type: z.string().min(1),
        sha256: z.string().regex(/^[0-9a-f]{64}$/),
    })
    .passthrough();

export const transferConflictSchema = z.object({
    table: transferTableSchema,
    reason: z.string(),
    count: z.number().int().positive(),
});

export const transferPlanSchema = z.object({
    profile_policy: transferProfilePolicySchema,
    user_ids: z.record(z.string().uuid()),
    source_ids: z.record(z.string().uuid()),
    identity_ids: z.record(z.string().uuid()),
    before_digest: z.string(),
    after_digest: z.string(),
    imported: z.record(transferRowSchema.array()),
    writes: z.record(transferRowSchema.array()),
    after: z.record(transferRowSchema.array()),
    conflicts: transferConflictSchema.array(),
    shared_accounts: z.number().int().nonnegative(),
    total_accounts: z.number().int().nonnegative(),
    preserved_profile_ids: z.string().uuid().array(),
});

export const transferArchiveSchema = z.object({
    id: z.string().uuid(),
    source: transferSnapshotSchema,
    target: transferSnapshotSchema,
    plan: transferPlanSchema,
});

export const transferApplicationResultSchema = z.object({
    already_applied: z.boolean(),
    committed: z.boolean(),
    verified_digest: z.string().regex(/^[0-9a-f]{64}$/),
});

export const transferRequestSchema = z.discriminatedUnion("action", [
    z.object({ action: z.literal("snapshot") }).strict(),
    z.object({ action: z.literal("media"), id: z.string().uuid() }).strict(),
    z
        .object({
            action: z.literal("prepare"),
            profile_policy: transferProfilePolicySchema,
            previous_run_id: z.string().uuid().optional(),
        })
        .strict(),
    z
        .object({ action: z.literal("copy-media"), run_id: z.string().uuid() })
        .strict(),
    z
        .object({ action: z.literal("apply"), run_id: z.string().uuid() })
        .strict(),
    z
        .object({ action: z.literal("rehearse"), run_id: z.string().uuid() })
        .strict(),
    z
        .object({ action: z.literal("verify"), run_id: z.string().uuid() })
        .strict(),
]);

export const transferEnvironmentSchema = z.object({
    SUPABASE_URL: z.string().url(),
    SUPABASE_DB_URL: z.string().min(1),
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
    FF_RELEASE_TRANSFER_TOKEN: z.string().regex(/^[0-9a-f]{64}$/),
    FF_RELEASE_TRANSFER_EXPIRES_AT: z.string().datetime(),
    FF_RELEASE_TRANSFER_TARGET: z.literal("qkkhkfepjhdgowmhhpyf"),
});

export const transferFailureMetadataSchema = z.object({
    code: z
        .string()
        .regex(/^(?:[0-9A-Z]{5}|[a-z_]{1,64})$/)
        .optional(),
    constraint_name: z
        .string()
        .regex(/^[a-z0-9_]+$/)
        .optional(),
    table_name: z
        .string()
        .regex(/^[a-z0-9_]+$/)
        .optional(),
    column_name: z
        .string()
        .regex(/^[a-z0-9_]+$/)
        .optional(),
});

export const transferReceiptSchema = z.object({
    sha256: z.string().regex(/^[0-9a-f]{64}$/),
    byte_size: z.number().int().positive(),
});

export type TransferTable = z.infer<typeof transferTableSchema>;
export type TransferRow = z.infer<typeof transferRowSchema>;
export type TransferProfilePolicy = z.infer<typeof transferProfilePolicySchema>;
export type TransferTableDefinition = z.infer<
    typeof transferTableDefinitionSchema
>;
export type TransferForeignKey = z.infer<typeof transferForeignKeySchema>;
export type TransferSnapshot = z.infer<typeof transferSnapshotSchema>;
export type TransferUser = z.infer<typeof transferUserSchema>;
export type TransferIdentity = z.infer<typeof transferIdentitySchema>;
export type TransferProfile = z.infer<typeof transferProfileSchema>;
export type TransferSource = z.infer<typeof transferSourceSchema>;
export type TransferMedia = z.infer<typeof transferMediaSchema>;
export type TransferConflict = z.infer<typeof transferConflictSchema>;
export type TransferPlan = z.infer<typeof transferPlanSchema>;
export type TransferArchive = z.infer<typeof transferArchiveSchema>;
export type TransferApplicationResult = z.infer<
    typeof transferApplicationResultSchema
>;
export type TransferRequest = z.infer<typeof transferRequestSchema>;
export type TransferEnvironment = z.infer<typeof transferEnvironmentSchema>;
export type TransferFailureMetadata = z.infer<
    typeof transferFailureMetadataSchema
>;
export type TransferReceipt = z.infer<typeof transferReceiptSchema>;
