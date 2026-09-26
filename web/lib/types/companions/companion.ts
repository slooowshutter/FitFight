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

export const limitedCompanionIdValues = [
    "limited-pangolin",
    "limited-platypus",
    "limited-spotted-quoll",
    "limited-fennec-fox",
    "limited-musk-ox",
    "limited-kookaburra",
    "limited-porcupine",
    "limited-bharal",
    "limited-golden-snub-nosed-monkey",
    "limited-proboscis-monkey",
    "limited-tree-kangaroo",
    "limited-gila-monster",
    "limited-tarsier",
    "limited-maned-wolf",
    "limited-fire-salamander",
    "limited-serval-stroll",
    "limited-puffin",
    "limited-numbat-sprint",
    "limited-coati-snooze",
    "limited-galago",
    "limited-frilled-lizard",
    "limited-okapi",
    "limited-hoatzin",
    "limited-quokka",
    "limited-numbat-stride",
    "limited-sifaka",
    "limited-secretary-bird-stride",
    "limited-rock-hyrax",
    "limited-serval-sprint",
    "limited-banded-mongoose",
    "limited-axolotl",
    "limited-thorny-devil-stroll",
    "limited-coati-sprint",
    "limited-tamandua",
    "limited-paca",
    "limited-jerboa",
    "limited-thorny-devil-coffee",
    "limited-kakapo",
    "limited-secretary-bird-snooze",
    "limited-markhor",
] as const;

export const companionIdValues = [...stockCompanionIdValues, ...limitedCompanionIdValues, "custom"] as const;

export const stockCompanionIdSchema = z.enum(stockCompanionIdValues);
export const companionIdSchema = z.enum(companionIdValues);
export const limitedCompanionIdSchema = z.enum(limitedCompanionIdValues);
export const companionPromptSchema = z.string().trim().max(1000);
export const savedCompanionPromptsSchema = z.array(companionPromptSchema.min(1));

export type StockCompanionId = z.infer<typeof stockCompanionIdSchema>;
export type CompanionId = z.infer<typeof companionIdSchema>;
export type SavedCompanionPrompts = z.infer<typeof savedCompanionPromptsSchema>;

export type LimitedCompanionId = z.infer<typeof limitedCompanionIdSchema>;
