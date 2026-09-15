import { z } from "zod";

export const suggestFightRequestSchema = z.object({
  suggested: z.boolean(),
}).strict();

export const suggestFightResponseSchema = z.object({
  suggested: z.boolean(),
}).strict();

export type SuggestFightRequest = z.infer<typeof suggestFightRequestSchema>;
export type SuggestFightResponse = z.infer<typeof suggestFightResponseSchema>;
