import { z } from "zod";
import { aiErrorCodeSchema } from "@/lib/types/ai/error";
import {
    blendApiKeySchema,
    blendWorkflowVersionSchema,
} from "@/lib/types/blend/workflow";

export const aiWorkflowValues = ["avatar", "fitness", "group_photo"] as const;
export const aiWorkflowSchema = z.enum(aiWorkflowValues);
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
    ]),
]);

export type AiWorkflow = z.infer<typeof aiWorkflowSchema>;
export type AiGroupCharacter = z.infer<typeof aiGroupCharacterSchema>;
export type CreateAiRunRequest = z.infer<typeof createAiRunRequestSchema>;
export type BlendEnvironment = z.infer<typeof blendEnvironmentSchema>;
export type AiWorkflowConfiguration = z.infer<
    typeof aiWorkflowConfigurationSchema
>;
export type AiAvatarResult = z.infer<typeof aiAvatarResultSchema>;
export type AiFitnessResult = z.infer<typeof aiFitnessResultSchema>;
export type AiRunResponse = z.infer<typeof aiRunResponseSchema>;
export type AiImageUrl = z.infer<typeof aiImageUrlSchema>;
export type BlendSingleImage = z.infer<typeof blendSingleImageSchema>;
export type BlendAvatarOutput = z.infer<typeof blendAvatarOutputSchema>;
export type BlendFitnessOutput = z.infer<typeof blendFitnessOutputSchema>;
export type BlendGroupPhotoOutput = z.infer<typeof blendGroupPhotoOutputSchema>;
