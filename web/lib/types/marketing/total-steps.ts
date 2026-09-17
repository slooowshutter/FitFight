import { z } from "zod";

export const marketingTotalStepsSchema = z.object({
    totalSteps: z.coerce.number().int().nonnegative(),
});

export type MarketingTotalSteps = z.infer<typeof marketingTotalStepsSchema>;
