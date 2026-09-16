import { z } from "zod";
import { fightVisibilitySchema } from "@/lib/types/fights/joinable-fight";

export const fightAdminConfigurationSchema = z.object({ user_id: z.preprocess((value) => value === "" ? undefined : value, z.string().uuid().optional()) });
export const administerFightRequestSchema = z.object({
    visibility: fightVisibilitySchema.optional(),
    recurring: z.boolean().optional(),
    action: z.enum(["stop_round", "pause_series"]).optional(),
}).strict().refine((value) => Object.keys(value).length > 0, "Choose an action");
export const administeredFightSchema = z.object({
    id: z.string().uuid(), state: z.string(), series_id: z.string().uuid().nullable(), ends_at: z.coerce.date(),
});
export const administeredSeriesSchema = z.object({
    id: z.string().uuid(), visibility: fightVisibilitySchema, paused_at: z.coerce.date().nullable(),
    current_fight_id: z.string().uuid().nullable(),
});
export type AdministerFightRequest = z.infer<typeof administerFightRequestSchema>;
