import { z } from "zod";

export const stockCompanionIdValues = [
    "badger",
    "raccoon",
    "red-panda",
    "otter",
    "rabbit",
    "fox",
    "bear",
    "boar",
    "sloth",
    "dog",
    "goat",
    "turtle",
] as const;

export const companionIdValues = [...stockCompanionIdValues, "custom"] as const;

export const stockCompanionIdSchema = z.enum(stockCompanionIdValues);
export const companionIdSchema = z.enum(companionIdValues);
export const companionPromptSchema = z.string().trim().max(1000);
export const savedCompanionPromptsSchema = z.array(companionPromptSchema.min(1));

export type StockCompanionId = z.infer<typeof stockCompanionIdSchema>;
export type CompanionId = z.infer<typeof companionIdSchema>;
export type SavedCompanionPrompts = z.infer<typeof savedCompanionPromptsSchema>;
