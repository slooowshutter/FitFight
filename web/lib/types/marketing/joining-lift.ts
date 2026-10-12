import { z } from "zod";

export const marketingJoiningLiftSchema = z.object({
    joiningLift: z.number().nullable(),
});

export type MarketingJoiningLift = z.infer<typeof marketingJoiningLiftSchema>;
