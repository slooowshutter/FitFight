import { z } from "zod";

/** The fields decoded by App Store build 113's membership model. */
export const legacyMembership113Schema = z.object({
  fight_id: z.string().uuid(),
  user_id: z.string().uuid(),
  state: z.string(),
  current_value: z.number().nullable(),
  rank: z.number().int().nullable(),
  final_value: z.number().nullable(),
}).strict();

export type LegacyMembership113 = z.infer<typeof legacyMembership113Schema>;
