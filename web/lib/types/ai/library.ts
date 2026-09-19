import { z } from "zod";
import { aiWorkflowSchema, aiImageUrlSchema } from "@/lib/types/ai/workflow";

export const aiImageStageValues = [
    "image_url",
    "resting",
    "soft",
    "average",
    "fit",
    "strong",
] as const;
export const aiImageStageSchema = z.enum(aiImageStageValues);
export const aiCompanionSelectionSchema = z
    .object({
        request_id: z.string().uuid().toLowerCase(),
        stage: aiImageStageSchema,
    })
    .strict();
export const aiLibraryImageSchema = z.object({
    stage: aiImageStageSchema,
    url: aiImageUrlSchema,
});
export const aiLibraryEntrySchema = z.object({
    request_id: z.string().uuid(),
    workflow: aiWorkflowSchema,
    description: z.string(),
    images: z.array(aiLibraryImageSchema),
});
export const aiLibraryRowSchema = aiLibraryEntrySchema
    .omit({ images: true })
    .extend({
        stage: aiImageStageSchema,
        image_url: aiImageUrlSchema,
    });

export type AiCompanionSelection = z.infer<typeof aiCompanionSelectionSchema>;
export type AiLibraryImage = z.infer<typeof aiLibraryImageSchema>;
export type AiLibraryEntry = z.infer<typeof aiLibraryEntrySchema>;
export type AiLibraryRow = z.infer<typeof aiLibraryRowSchema>;
