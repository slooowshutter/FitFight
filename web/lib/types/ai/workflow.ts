import { z } from "zod";
import { aiErrorCodeSchema } from "@/lib/types/ai/error";
import {
    blendApiKeySchema,
    blendWorkflowVersionSchema,
} from "@/lib/types/blend/workflow";

export const aiWorkflowValues = ["avatar", "fitness", "group_photo", "companion_lines"] as const;
export const aiWorkflowSchema = z.enum(aiWorkflowValues);
export const companionLanguageValues = ["en", "fr"] as const;
const singleLinePattern = /^[^\n\r\u2028\u2029]*$/;
/** A custom companion's name and line, suggested by Blend or typed by its owner. */
export const companionLabelSchema = z.object({
    name: z.string().trim().min(1).max(24).regex(singleLinePattern, "Use one line"),
    line: z.string().trim().min(1).max(60).regex(singleLinePattern, "Use one line"),
});
/** Saved suggestions are read as stored, so tightening the limits above never breaks reading earlier batches. */
export const storedCompanionLabelSchema = z.object({ name: z.string(), line: z.string() });
export const aiGroupCharacterSchema = z
    .object({
        avatar_request_id: z.string().uuid().toLowerCase(),
        identity_details: z.string().trim().min(1).max(1000),
    })
    .strict();
export const createAiRunRequestSchema = z.discriminatedUnion("workflow", [
    z
        .object({
            workflow: z.literal("avatar"),
            parameters: z
                .object({ description: z.string().trim().min(1).max(1000) })
                .strict(),
        })
        .strict(),
    z
        .object({
            workflow: z.literal("fitness"),
            parameters: aiGroupCharacterSchema,
        })
        .strict(),
    z
        .object({
            workflow: z.literal("companion_lines"),
            parameters: z
                .object({
                    avatar_request_id: z.string().uuid().toLowerCase(),
                    description: z.string().trim().min(1).max(1000),
                    language: z.enum(companionLanguageValues),
                    avoid: z.array(companionLabelSchema).max(12),
                })
                .strict(),
        })
        .strict(),
    z
        .object({
            workflow: z.literal("group_photo"),
            parameters: z
                .object({
                    characters: z
                        .array(aiGroupCharacterSchema)
                        .min(2)
                        .max(5)
                        .refine(
                            (characters) =>
                                new Set(
                                    characters.map(
                                        (character) =>
                                            character.avatar_request_id,
                                    ),
                                ).size === characters.length,
                            "Each character needs a different avatar request",
                        ),
                    scene: z.string().trim().min(1).max(1000),
                })
                .strict(),
        })
        .strict(),
]);

export const blendEnvironmentSchema = z.object({
    BLEND_API_KEY: blendApiKeySchema,
});
export const aiWorkflowConfigurationSchema = z.object({
    version: blendWorkflowVersionSchema,
    creditPrice: z.coerce.number().int().positive().max(100_000),
});
export const legacyAvatarVersionId = "bbf425cb-1c8a-4dfa-9f0d-637f22e8f4e1";

/**
 * Non-secret Blend settings. Only BLEND_API_KEY lives in the environment.
 * Omit versionId to run the latest published version. Omit creditPrice to keep
 * credit-funded starts closed, with no invented default.
 */
export const blendConfiguration: {
    limits: {
        globalDailyStarts: number;
        globalConcurrentRuns: number;
        providerRequestsPerMinute: number;
    };
    workflows: Record<
        AiWorkflow,
        { workflowId: string; versionId?: string; creditPrice?: number }
    >;
} = {
    limits: {
        globalDailyStarts: 500,
        globalConcurrentRuns: 20,
        providerRequestsPerMinute: 60,
    },
    workflows: {
        avatar: {
            workflowId: "c405d12d-fa25-4e67-8d4d-8336e741cbbc",
            creditPrice: 1,
        },
        fitness: { workflowId: "fa770c5b-25ba-46cc-a758-a08aeebc1c92" },
        group_photo: { workflowId: "f740d71e-06fe-41d4-a92d-a85c90abd3f9" },
        companion_lines: { workflowId: "8df8fe50-aefb-4855-b421-7bfc89f7e825" },
    },
};

export const aiImageHostValues = [
    "supabase.tryblend.ai",
    "cdn.tryblend.ai",
] as const;
export const aiImageUrlSchema = z
    .string()
    .url()
    .max(4096)
    .refine((value) => {
        const url = new URL(value);
        return (
            url.protocol === "https:" &&
            url.username === "" &&
            url.password === "" &&
            url.port === "" &&
            aiImageHostValues.some((host) => host === url.hostname)
        );
    });
export const aiAvatarResultSchema = z.object({ image_url: aiImageUrlSchema });
export const aiFitnessResultSchema = z.object({
    resting: aiImageUrlSchema,
    soft: aiImageUrlSchema,
    average: aiImageUrlSchema,
    fit: aiImageUrlSchema,
    strong: aiImageUrlSchema,
});
export const aiCompanionLinesResultSchema = z.object({
    options: z.array(companionLabelSchema).length(4),
});
export const blendSingleImageSchema = z
    .array(
        z.object({
            status: z.literal("completed"),
            parts: z.tuple([
                z.object({ type: z.literal("image"), url: aiImageUrlSchema }),
            ]),
        }),
    )
    .length(1)
    .transform((items) => items[0].parts[0].url);
export const blendAvatarOutputSchema = z
    .object({ avatar: blendSingleImageSchema })
    .transform(({ avatar }) => ({ image_url: avatar }));
export const blendFitnessOutputSchema = z.object({
    resting: blendSingleImageSchema,
    soft: blendSingleImageSchema,
    average: blendSingleImageSchema,
    fit: blendSingleImageSchema,
    strong: blendSingleImageSchema,
});
export const blendGroupPhotoOutputSchema = z
    .object({ group_photo: blendSingleImageSchema })
    .transform(({ group_photo }) => ({ image_url: group_photo }));
/** The LLM node returns the options as a JSON part, or as text that holds the JSON, sometimes in a ```json fence. */
export const blendCompanionLinesOutputSchema = z
    .object({
        options: z
            .array(
                z.object({
                    status: z.literal("completed"),
                    parts: z.tuple([
                        z
                            .discriminatedUnion("type", [
                                z.object({ type: z.literal("json"), data: z.unknown() }),
                                z.object({ type: z.literal("text"), text: z.string() }),
                            ])
                            .transform((part, context) => {
                                if (part.type === "json") return part.data;
                                const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(part.text.trim());
                                try {
                                    const parsed: unknown = JSON.parse(fenced ? fenced[1] : part.text);
                                    return parsed;
                                } catch {
                                    context.addIssue({ code: z.ZodIssueCode.custom, message: "The options are not JSON" });
                                    return z.NEVER;
                                }
                            })
                            .pipe(aiCompanionLinesResultSchema),
                    ]),
                }),
            )
            .length(1),
    })
    .transform(({ options }) => options[0].parts[0]);

export const aiRunResponseSchema = z.union([
    z.discriminatedUnion("status", [
        z.object({
            request_id: z.string().uuid(),
            workflow: aiWorkflowSchema,
            status: z.literal("pending"),
            poll_after_seconds: z.number().int().positive(),
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: aiWorkflowSchema,
            status: z.literal("running"),
            poll_after_seconds: z.number().int().positive(),
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: aiWorkflowSchema,
            status: z.literal("failed"),
            code: aiErrorCodeSchema,
            error: z.string(),
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: aiWorkflowSchema,
            status: z.literal("cancelled"),
            code: aiErrorCodeSchema,
            error: z.string(),
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: aiWorkflowSchema,
            status: z.literal("start_unconfirmed"),
            code: z.literal("ai_start_unconfirmed"),
            error: z.string(),
        }),
    ]),
    z.discriminatedUnion("workflow", [
        z.object({
            request_id: z.string().uuid(),
            workflow: z.literal("avatar"),
            status: z.literal("completed"),
            data: aiAvatarResultSchema,
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: z.literal("fitness"),
            status: z.literal("completed"),
            data: aiFitnessResultSchema,
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: z.literal("group_photo"),
            status: z.literal("completed"),
            data: aiAvatarResultSchema,
        }),
        z.object({
            request_id: z.string().uuid(),
            workflow: z.literal("companion_lines"),
            status: z.literal("completed"),
            data: aiCompanionLinesResultSchema,
        }),
    ]),
]);

export type AiWorkflow = z.infer<typeof aiWorkflowSchema>;
export type AiGroupCharacter = z.infer<typeof aiGroupCharacterSchema>;
export type CompanionLabel = z.infer<typeof companionLabelSchema>;
export type CreateAiRunRequest = z.infer<typeof createAiRunRequestSchema>;
export type BlendEnvironment = z.infer<typeof blendEnvironmentSchema>;
export type AiWorkflowConfiguration = z.infer<
    typeof aiWorkflowConfigurationSchema
>;
export type AiAvatarResult = z.infer<typeof aiAvatarResultSchema>;
export type AiFitnessResult = z.infer<typeof aiFitnessResultSchema>;
export type AiCompanionLinesResult = z.infer<typeof aiCompanionLinesResultSchema>;
export type AiRunResponse = z.infer<typeof aiRunResponseSchema>;
export type AiImageUrl = z.infer<typeof aiImageUrlSchema>;
export type BlendSingleImage = z.infer<typeof blendSingleImageSchema>;
export type BlendAvatarOutput = z.infer<typeof blendAvatarOutputSchema>;
export type BlendFitnessOutput = z.infer<typeof blendFitnessOutputSchema>;
export type BlendGroupPhotoOutput = z.infer<typeof blendGroupPhotoOutputSchema>;
export type BlendCompanionLinesOutput = z.infer<typeof blendCompanionLinesOutputSchema>;
