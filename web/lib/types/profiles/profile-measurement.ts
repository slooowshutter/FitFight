import { z } from "zod";
import { profileEntryPointValues } from "./shared-profile";

export const profileMeasurementGroupSchema = z.object({
    kind: z.enum(["view", "friend_request", "friend_accept", "shared_fight"]),
    source: z.enum(profileEntryPointValues).nullable(), events: z.number().int().nonnegative(),
    unique_actors: z.number().int().nonnegative(), qualifying: z.number().int().nonnegative(),
});
export type ProfileMeasurementGroup = z.infer<typeof profileMeasurementGroupSchema>;
