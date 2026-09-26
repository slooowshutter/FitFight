import { z } from "zod";
import { fightVisibilitySchema } from "@/lib/types/fights/joinable-fight";
import { fightStateValues } from "@/lib/types/fights/membership-decision";
import { profileSchema } from "@/lib/types/profiles/profile";

export const fightAdminConfigurationSchema = z.object({ user_id: z.preprocess((value) => value === "" ? undefined : value, z.string().uuid().optional()) });
export const administerFightRequestSchema = z.object({
    visibility: fightVisibilitySchema.optional(),
    recurring: z.boolean().optional(),
    action: z.enum(["stop_round", "pause_series"]).optional(),
}).strict().refine((value) => Object.keys(value).length > 0, "Choose an action");
export const administeredFightSchema = z.object({
    id: z.string().uuid(), state: z.enum(fightStateValues), series_id: z.string().uuid().nullable(), ends_at: z.coerce.date(),
});
export const administeredSeriesSchema = z.object({
    id: z.string().uuid(), visibility: fightVisibilitySchema, paused_at: z.coerce.date().nullable(),
    current_fight_id: z.string().uuid().nullable(),
});
export const suggestedSeriesSchema = administeredSeriesSchema.extend({
    owner_id: z.string().uuid(), name: z.string(), join_code: z.string().nullable(), suggested: z.boolean(),
});
export const suggestedFightOwnerSchema = profileSchema.pick({ handle: true, display_name: true });

export type AdministerFightRequest = z.infer<typeof administerFightRequestSchema>;
export type SuggestedSeries = z.infer<typeof suggestedSeriesSchema>;
export type SuggestedFightOwner = z.infer<typeof suggestedFightOwnerSchema>;
