import { z } from "zod";
import {
    companionIdSchema,
    companionPromptSchema,
} from "@/lib/types/companions/companion";
import { mediaObjectSchema } from "@/lib/types/media/media";
import { timeZoneSchema } from "@/lib/types/time/time-zone";

export const profileSchema = z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
    display_name: z.string(),
    handle_set_at: z.string().datetime({ offset: true }).nullable(),
    referral_code: z.string().uuid(),
    avatar: mediaObjectSchema.nullable(),
    companion_id: companionIdSchema.nullable().default(null),
    companion_prompt: z.string().nullable().default(null),
    time_zone: timeZoneSchema.optional(),
});

export const profileDatabaseRowSchema = profileSchema.omit({ avatar: true }).extend({
    avatar_media_id: z.string().uuid().nullable(),
    time_zone: timeZoneSchema.nullable(),
});

export const updateProfileRequestSchema = z
    .object({
        handle: z
            .string()
            .transform((value) =>
                value
                    .trim()
                    .replace(/^@+|@+$/g, "")
                    .toLowerCase(),
            )
            .pipe(
                z
                    .string()
                    .regex(
                        /^[a-z0-9_]{2,30}$/,
                        "Use 2–30 letters, numbers, or underscore",
                    ),
            )
            .optional(),
        display_name: z
            .string()
            .trim()
            .min(1, "Enter a display name")
            .optional(),
        avatar_media_id: z.string().uuid().nullable().optional(),
        companion_id: companionIdSchema.optional(),
        companion_prompt: companionPromptSchema.nullable().optional(),
        time_zone: timeZoneSchema.optional(),
    })
    .strict()
    .superRefine((input, ctx) => {
        if (
            input.handle === undefined &&
            input.display_name === undefined &&
            input.avatar_media_id === undefined &&
            input.companion_id === undefined &&
            input.companion_prompt === undefined &&
            input.time_zone === undefined
        ) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "Supply a username, display name, photo, companion, or time zone",
            });
        }
        if (input.companion_id === "custom" && !input.companion_prompt) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                path: ["companion_prompt"],
                message: "Describe your animal",
            });
        }
    });

export type Profile = z.infer<typeof profileSchema>;
export type ProfileDatabaseRow = z.infer<typeof profileDatabaseRowSchema>;
export type UpdateProfileRequest = z.infer<typeof updateProfileRequestSchema>;
