import { z } from "zod";

/** Cumulative Apple Health steps from the Fight start through this cutoff. */
export const fightStepCheckpointSchema = z.object({
  day: z.string().date(),
  cutoff_at: z.string().datetime({ offset: true }),
  steps: z.number().int().min(0).max(2_147_483_647),
}).strict();

export type FightStepCheckpoint = z.infer<typeof fightStepCheckpointSchema>;
