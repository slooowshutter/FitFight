import { z } from "zod";
import { aiWorkflowSchema } from "@/lib/types/ai/workflow";
import { mediaObjectSchema } from "@/lib/types/media/media";

export const aiImageStageValues = [
    "image_url",
    "resting",
    "soft",
    "average",
    "fit",
    "strong",
] as const;
export const aiImageStageSchema = z.enum(aiImageStageValues);
export const saveAiImagesSchema = z
    .object({
        description: z.string().trim().min(1).max(1000),
        images: z
            .array(
                z
                    .object({
                        stage: aiImageStageSchema,
                        media_id: z.string().uuid().toLowerCase(),
                    })
                    .strict(),
            )
            .min(1)
            .max(5),
    })
    .strict()
    .refine(
        (input) =>
            new Set(input.images.map((image) => image.stage)).size ===
                input.images.length &&
            new Set(input.images.map((image) => image.media_id)).size ===
                input.images.length,
        "Each image needs a distinct stage and media ID",
    );
export const aiLibraryImageSchema = z.object({
    stage: aiImageStageSchema,
    media: mediaObjectSchema,
});
export const aiLibraryEntrySchema = z.object({
    request_id: z.string().uuid(),
    workflow: aiWorkflowSchema,
    description: z.string(),
    images: z.array(aiLibraryImageSchema),
});
export const aiLibraryRowSchema = z.object({
    request_id: z.string().uuid(),
    workflow: aiWorkflowSchema,
    description: z.string(),
    stage: aiImageStageSchema,
    media_id: z.string().uuid(),
});
export const aiSourcePortraitSchema = z.object({
    id: z.string().uuid(),
    result: z.record(z.unknown()).nullable(),
    object_path: z.string().nullable(),
});

export type AiImageStage = z.infer<typeof aiImageStageSchema>;
export type SaveAiImages = z.infer<typeof saveAiImagesSchema>;
export type AiLibraryImage = z.infer<typeof aiLibraryImageSchema>;
export type AiLibraryEntry = z.infer<typeof aiLibraryEntrySchema>;
export type AiLibraryRow = z.infer<typeof aiLibraryRowSchema>;
export type AiSourcePortrait = z.infer<typeof aiSourcePortraitSchema>;
