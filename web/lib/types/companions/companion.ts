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

export const stockCompanionIdSchema = z.enum(stockCompanionIdValues);

export type StockCompanionId = z.infer<typeof stockCompanionIdSchema>;
