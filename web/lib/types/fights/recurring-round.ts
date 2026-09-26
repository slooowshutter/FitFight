import { z } from "zod";
import { recordTimestampSchema } from "@/lib/types/profiles/profile-results";

export const recurringRoundSchema = z.object({
    id: z.string().uuid(), series_id: z.string().uuid().nullable(), state: z.string(),
    starts_at: recordTimestampSchema, ends_at: recordTimestampSchema,
});
export const recurringSeriesSchema = z.object({
    recurring: z.boolean(), paused_at: z.coerce.date().nullable(), current_fight_id: z.string().uuid().nullable(),
});
export type RecurringRound = z.infer<typeof recurringRoundSchema>;
export type RecurringSeries = z.infer<typeof recurringSeriesSchema>;
