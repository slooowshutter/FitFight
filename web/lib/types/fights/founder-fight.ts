import { z } from "zod";
import type { EnvironmentName } from "@/lib/types/environment/environment";

/** Marc's account in each environment. Account IDs never change. */
export const founderUserIds: Record<EnvironmentName, string> = {
    beta: "87434630-dd64-4465-b79b-fd99e35368be",
    production: "854ed9b9-5de9-4d85-b10e-e201deb999de",
};

export const FOUNDER_FIGHT_DAYS = 30;

export const founderChallengerSchema = z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
    display_name: z.string(),
    fight_id: z.string().uuid(),
    day: z.number().int(),
    days: z.number().int(),
    steps: z.coerce.number(),
    founder_steps: z.coerce.number(),
    state: z.string(),
    wins: z.number().int(),
    losses: z.number().int(),
    draws: z.number().int(),
});

export const founderChallengersSchema = z.object({
    challengers: z.array(founderChallengerSchema),
});

export type FounderChallenger = z.infer<typeof founderChallengerSchema>;
export type FounderChallengers = z.infer<typeof founderChallengersSchema>;
