import { z } from "zod";
import { companionLanguageValues } from "@/lib/types/ai/workflow";

/** A workflow id with this prefix runs in web/lib/ai/workflows.ts; any other id is a Blend workflow. */
export const aiRunnerPrefix = "fitfight:";

/** The FitFight AI workflows in web/lib/ai/workflows.ts. The first five also answer `/api/v1/ai/runs`. */
export const aiRunnerWorkflowValues = [
    "avatar",
    "fitness",
    "group_photo",
    "companion_lines",
    "prompt_check",
    "trail",
    "race_start",
] as const;
export const aiStepKindValues = ["text", "image"] as const;
export const aiStepStatusValues = ["completed", "failed"] as const;
export const aiStepProviderValues = ["openrouter", "azure"] as const;
export const aiReasoningValues = ["low", "medium", "high"] as const;

/** One model call as `private.ai_steps` keeps it. */
export const aiStepRecordSchema = z.object({
    request_id: z.string().uuid().nullable(),
    run_id: z.string().min(1),
    workflow: z.string().min(1),
    step: z.string().min(1),
    step_id: z.string().min(1),
    attempt: z.number().int().min(1),
    kind: z.enum(aiStepKindValues),
    provider: z.enum(aiStepProviderValues),
    model: z.string().min(1),
    model_used: z.string().nullable(),
    upstream: z.string().nullable(),
    status: z.enum(aiStepStatusValues),
    error: z.string().nullable(),
    started_at: z.date(),
    duration_ms: z.number().int().nonnegative(),
    first_token_ms: z.number().int().nonnegative().nullable(),
    input_tokens: z.number().int().nonnegative().nullable(),
    output_tokens: z.number().int().nonnegative().nullable(),
    reasoning_tokens: z.number().int().nonnegative().nullable(),
    cached_tokens: z.number().int().nonnegative().nullable(),
    cost_usd: z.number().nonnegative().nullable(),
    cost_source: z.enum(["provider", "price_list"]).nullable(),
    input: z.record(z.unknown()),
    output: z.unknown(),
    code_version: z.string().min(1),
});

/**
 * Sunburst drawings run on Blend's Azure regions first, paid with Azure credits: the same resources, keys and per-minute
 * limits Blend uses (20 Oct 2026). A region without its key in the environment is skipped. Not secrets, so they live here.
 */
export const azureImageRegions = [
    { name: "Sweden Central", endpoint: "https://blendai-sweden-central.services.ai.azure.com/openai/v1", keyEnv: "AZURE_IMAGE_SWEDENCENTRAL_API_KEY", perMinute: 3 },
    { name: "Poland Central", endpoint: "https://blendai-poland-central.services.ai.azure.com/openai/v1", keyEnv: "AZURE_IMAGE_POLANDCENTRAL_API_KEY", perMinute: 3 },
    { name: "East US 2", endpoint: "https://blendai-east-us-2.services.ai.azure.com/openai/v1", keyEnv: "AZURE_IMAGE_EASTUS2_API_KEY", perMinute: 2 },
    { name: "West US 3", endpoint: "https://blendai-west-us-3.services.ai.azure.com/openai/v1", keyEnv: "AZURE_IMAGE_WESTUS3_API_KEY", perMinute: 2 },
    { name: "UAE North", endpoint: "https://blendai-uae-north.services.ai.azure.com/openai/v1", keyEnv: "AZURE_IMAGE_UAENORTH_API_KEY", perMinute: 2 },
] as const;

/** OpenAI's list price for Sunburst, dollars per million tokens: what a drawing paid with Azure credits is worth. */
export const sunburstListPrice = { textInput: 5, imageInput: 8, output: 30 } as const;

/** Azure's answer to `POST /images/edits`: base64 pictures and the tokens, split by text and pictures. */
export const azureImageResponseSchema = z.object({
    data: z.array(z.object({ b64_json: z.string().min(1) })).min(1),
    usage: z.object({
        input_tokens: z.number().int().nonnegative(),
        input_tokens_details: z.object({
            text_tokens: z.number().int().nonnegative(),
            image_tokens: z.number().int().nonnegative(),
        }),
        output_tokens: z.number().int().nonnegative(),
    }).nullish(),
});

/** OpenRouter's usage accounting on a text call; cost is in dollars. */
export const openRouterUsageSchema = z.object({ cost: z.number().nonnegative() });

export const openRouterStreamErrorSchema = z.object({
    code: z.union([z.number(), z.string()]).pipe(z.coerce.number().int().min(100).max(599)),
    message: z.string(),
});

/** OpenRouter's answer to `POST /images`: base64 pictures, tokens and the dollar cost. */
export const openRouterImageResponseSchema = z.object({
    model: z.string().nullish(),
    provider: z.string().nullish(),
    data: z.array(z.object({ b64_json: z.string().min(1) })).min(1),
    // Read after a paid drawing: a missing or null figure is logged empty, never a reason to draw again.
    usage: z
        .object({
            prompt_tokens: z.number().int().nonnegative().nullish(),
            completion_tokens: z.number().int().nonnegative().nullish(),
            cost: z.number().nonnegative().nullish(),
        })
        .nullish(),
});

/**
 * What each workflow is started with. Checked once at the start, because fight images retry with inputs read
 * back from the database. portraits are picture links, in order.
 */
const portraitsSchema = z.array(z.string().url()).min(1).max(16);
export const avatarInputSchema = z.object({ request_id: z.string().uuid(), description: z.string().min(1) });
export const fitnessInputSchema = z.object({ request_id: z.string().uuid(), portraits: portraitsSchema.length(1), identity_details: z.string() });
export const groupPhotoInputSchema = z.object({ request_id: z.string().uuid(), portraits: portraitsSchema, scene: z.string(), cast_roster: z.string() });
export const companionLinesInputSchema = z.object({
    request_id: z.string().uuid(),
    portraits: portraitsSchema.length(1),
    description: z.string(),
    language: z.enum(companionLanguageValues),
    avoid: z.string(),
});
export const promptCheckInputSchema = z.object({ request_id: z.string().uuid(), description: z.string().min(1), language: z.enum(companionLanguageValues) });
export const trailInputSchema = z.object({ portraits: portraitsSchema, cast_roster: z.string(), scene: z.string() });
export const raceStartInputSchema = z.object({
    portraits: portraitsSchema,
    cast_roster: z.string(),
    crowd_size: z.string(),
    crowd_companions: z.string(),
});

export const aiRunnerWorkflowSchema = z.enum(aiRunnerWorkflowValues);

/** Checkpointed by the Workflow SDK before the separate storage step starts. */
export const aiDrawnImageSchema = z.object({
    png: z.instanceof(Uint8Array),
    runId: z.string().min(1),
    stepId: z.string().min(1),
});

export type AiDrawnImage = z.infer<typeof aiDrawnImageSchema>;
export type AiStepRecord = z.infer<typeof aiStepRecordSchema>;
export type OpenRouterStreamError = z.infer<typeof openRouterStreamErrorSchema>;
export type AiReasoning = (typeof aiReasoningValues)[number];

/** A text or vision call. {{name}} in system and prompt is filled from vars. No reasoning sends none, as Blend did. */
export type AiTextStep = {
    requestId: string | null;
    name: string;
    model: string;
    system?: string;
    prompt: string;
    vars?: Record<string, string>;
    images?: string[];
    temperature?: number;
    reasoning?: AiReasoning;
};

/** A drawing. images are the input pictures, in order. */
export type AiImageStep = {
    requestId: string | null;
    name: string;
    model: string;
    prompt: string;
    vars?: Record<string, string>;
    images: string[];
    size: `${number}x${number}`;
};

export type AvatarInput = z.infer<typeof avatarInputSchema>;
export type FitnessInput = z.infer<typeof fitnessInputSchema>;
export type GroupPhotoInput = z.infer<typeof groupPhotoInputSchema>;
export type CompanionLinesInput = z.infer<typeof companionLinesInputSchema>;
export type PromptCheckInput = z.infer<typeof promptCheckInputSchema>;
export type TrailInput = z.infer<typeof trailInputSchema>;
export type RaceStartInput = z.infer<typeof raceStartInputSchema>;
