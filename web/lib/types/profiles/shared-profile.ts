import { z } from "zod";
import { companionIdSchema } from "@/lib/types/companions/companion";
import { recordTimestampSchema } from "./profile-results";
import { profileStepStatisticsSchema } from "./profile-step-statistics";

export const profileCountRowSchema = z.object({ n: z.number().int().nonnegative() });
export const profileIdentifierRowSchema = z.object({ id: z.string().uuid() });
export const profileSharedFightRowSchema = z.object({ user_id: z.string().uuid(), id: z.string().uuid() });

export const profileUserIDSchema = z.string().uuid().transform((value) => value.toLowerCase());

export const profileAudienceValues = ["private", "public"] as const;
export const activityAudienceValues = ["off", "friends", "opponents", "public"] as const;
export const friendshipStateValues = ["none", "outgoing", "incoming", "friends", "self"] as const;
export const profileEntryPointValues = ["standings", "participants", "feed", "comments", "reactions", "feedback", "friends", "lookup"] as const;
export const profilePreviewAudienceValues = ["friend", "opponent", "past_opponent", "stranger"] as const;

export const profileSettingsSchema = z.object({
    competitive: z.boolean(),
    audience: z.enum(profileAudienceValues),
    activity_audience: z.enum(activityAudienceValues),
    activity_days: z.union([z.literal(7), z.literal(30)]),
    artwork_allowed: z.boolean(),
    revision: z.number().int().nonnegative(),
});

export const defaultProfileSettings = profileSettingsSchema.parse({
    competitive: false, audience: "private", activity_audience: "off", activity_days: 7,
    artwork_allowed: false, revision: 0,
});

export const updateProfileSettingsSchema = profileSettingsSchema
    .omit({ revision: true })
    .partial()
    .strict()
    .refine((input) => Object.keys(input).length > 0, "Choose a setting to update");

export const sharedIdentitySchema = z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
    display_name: z.string(),
    companion_id: companionIdSchema.nullable(),
    avatar_url: z.string().url().nullable(),
});

export const profileCountsSchema = z.object({
    played: z.number().int().nonnegative(),
    wins: z.number().int().nonnegative(),
    win_rate: z.number().min(0).max(1).nullable(),
});

export const profileRecordSchema = profileCountsSchema.extend({
    categories: z.object({
        public: profileCountsSchema,
        private: profileCountsSchema,
        unknown: profileCountsSchema,
    }),
    excluded: z.number().int().nonnegative(),
});

export const rivalryRecordSchema = z.object({
    wins: z.number().int().nonnegative(),
    losses: z.number().int().nonnegative(),
    draws: z.number().int().nonnegative(),
    rematch: z.object({
        duration_seconds: z.number().int().positive(),
        duration_days: z.number().int().positive().nullable().optional(),
        action_text: z.string().nullable(),
    }).nullable(),
});

export const profileRivalrySummarySchema = z.object({ identity: sharedIdentitySchema, rivalry: rivalryRecordSchema });

export const activityDaySchema = z.object({
    day: z.string().date(),
    steps: z.number().nonnegative(),
    time_zone: z.string().nullable(),
    updated_at: recordTimestampSchema,
    finalized: z.boolean(),
});

export const sharedProfileSchema = z.object({
    identity: sharedIdentitySchema,
    access: z.enum(["owner", "shared", "private"]),
    competitive: z.boolean(),
    friendship: z.enum(friendshipStateValues),
    record: profileRecordSchema.nullable(),
    rivalry: rivalryRecordSchema.nullable(),
    activity: z.object({
        metric: z.literal("steps"),
        days: z.union([z.literal(7), z.literal(30)]),
        values: z.array(activityDaySchema),
    }).nullable(),
    step_statistics: profileStepStatisticsSchema.nullable().optional(),
    artwork: z.object({ id: z.string().uuid(), image_path: z.string() }).nullable(),
    view_measurement_enabled: z.boolean(),
});

export const profileLookupSchema = z.object({
    handle: z.string().trim().transform((value) => value.replace(/^@/, "").toLowerCase())
        .pipe(z.string().regex(/^[a-z0-9_]{2,30}$/, "Enter an exact username")),
});

export const profileViewRequestSchema = z.object({
    event_id: z.string().uuid(),
    source: z.enum(profileEntryPointValues),
}).strict();

export const profileReportRequestSchema = z.object({
    reason: z.string().trim().min(1).max(1000),
}).strict();

export const profileReadQuerySchema = z.object({
    preview: z.enum(profilePreviewAudienceValues).optional(),
});

export const profilePageQuerySchema = z.object({
    cursor: z.string().uuid().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    shared: z.enum(["true", "false"]).default("false"),
});

export const profileRelationshipSchema = z.object({
    owner: z.boolean(),
    friend: z.boolean(),
    current_opponent: z.boolean(),
    blocked: z.boolean(),
});

export const profileAccessRowSchema = z.object({
    time_zone: z.string(),
    identity: sharedIdentitySchema.omit({ avatar_url: true }),
    avatar_path: z.string().nullable(),
    companion_image_url: z.string().url().nullish(),
    settings: profileSettingsSchema,
    relationship: profileRelationshipSchema,
    friendship: z.enum(friendshipStateValues),
});

export const profileFeatureConfigSchema = z.object({
    measurement: z.enum(["true", "false"]).default("false").transform((value) => value === "true"),
});

export type ProfileSettings = z.infer<typeof profileSettingsSchema>;
export type ProfileActivityDay = z.infer<typeof activityDaySchema>;
export type UpdateProfileSettings = z.infer<typeof updateProfileSettingsSchema>;
export type SharedIdentity = z.infer<typeof sharedIdentitySchema>;
export type ProfileCounts = z.infer<typeof profileCountsSchema>;
export type ProfileRecord = z.infer<typeof profileRecordSchema>;
export type RivalryRecord = z.infer<typeof rivalryRecordSchema>;
export type SharedProfile = z.infer<typeof sharedProfileSchema>;
export type ProfileViewRequest = z.infer<typeof profileViewRequestSchema>;
export type ProfilePageQuery = z.infer<typeof profilePageQuerySchema>;
export type ProfileRelationship = z.infer<typeof profileRelationshipSchema>;
export type ProfilePreviewAudience = (typeof profilePreviewAudienceValues)[number];
export type ProfileAccess = { identity: boolean; record: boolean; activity: boolean; shared: boolean };

export type ProfileRivalrySummary = z.infer<typeof profileRivalrySummarySchema>;

export type ProfileCountRow = z.infer<typeof profileCountRowSchema>;
export type ProfileIdentifierRow = z.infer<typeof profileIdentifierRowSchema>;
export type ProfileSharedFightRow = z.infer<typeof profileSharedFightRowSchema>;
