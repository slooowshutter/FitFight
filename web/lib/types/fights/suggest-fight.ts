import { z } from "zod";
import { administeredSeriesSchema } from "@/lib/types/admin/fight-administration";

export const suggestedSeriesRowSchema = administeredSeriesSchema.extend({
    owner_id: z.string().uuid(),
    join_code: z.string().nullable(),
    name: z.string(),
    suggested: z.boolean(),
    actor_name: z.string(),
});
export type SuggestedSeriesRow = z.infer<typeof suggestedSeriesRowSchema>;

export const suggestFightRequestSchema = z
    .object({
        suggested: z.boolean(),
    })
    .strict();

export const suggestFightResponseSchema = z
    .object({
        suggested: z.boolean(),
    })
    .strict();

export type SuggestFightRequest = z.infer<typeof suggestFightRequestSchema>;
export type SuggestFightResponse = z.infer<typeof suggestFightResponseSchema>;
