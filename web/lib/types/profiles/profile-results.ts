import { z } from "zod";

export const profileResultValues = ["win", "loss", "draw", "withdrawn", "removed", "incomplete", "cancelled", "ongoing", "solo", "not_entered", "unavailable"] as const;
export const recordCategoryValues = ["public", "private", "unknown"] as const;
export const recordTimestampSchema = z.string().refine((value) => Number.isFinite(Date.parse(value))).transform((value) => new Date(value).toISOString());

export const participationFactSchema = z.object({
    user_id: z.string().uuid(),
    entered_at: recordTimestampSchema.nullable(),
    departed_at: recordTimestampSchema.nullable(),
    departure: z.enum(["voluntary", "removed", "unknown"]).nullable(),
    state: z.string(),
    rank: z.number().int().positive().nullable(),
    final_value: z.coerce.number().nonnegative().nullable(),
    complete: z.boolean().nullable(),
    finalized_at: recordTimestampSchema.nullable(),
    reliable: z.boolean(),
});

export const resultEvidenceSummarySchema = z.object({
    field_size: z.number().int().nonnegative(), complete_finishers: z.number().int().nonnegative(),
    first_place_finishers: z.number().int().nonnegative(), verified: z.boolean(),
});

export const fightRecordFactSchema = z.object({
    history_id: z.string().uuid(),
    summary: resultEvidenceSummarySchema.nullable(),
    id: z.string().uuid(),
    state: z.string(),
    starts_at: recordTimestampSchema,
    ends_at: recordTimestampSchema,
    calendar_days: z.number(),
    category: z.enum(recordCategoryValues),
    name: z.string(),
    action_text: z.string().nullable(),
    outcome_rule: z.string(),
    members: z.array(participationFactSchema),
});

export const profileHistoryRowSchema = z.object({
    id: z.string().uuid(),
    fight_id: z.string().uuid().nullable(),
    name: z.string().nullable(),
    starts_at: z.string(),
    ends_at: z.string(),
    category: z.enum(recordCategoryValues),
    result: z.enum(profileResultValues),
    placement: z.number().int().positive().nullable(),
    field_size: z.number().int().nonnegative(),
    counted: z.boolean(),
    complete: z.boolean().nullable(),
});

export const profileHistoryPageSchema = z.object({
    results: z.array(profileHistoryRowSchema),
    next_cursor: z.string().uuid().nullable(),
});

export type ParticipationFact = z.infer<typeof participationFactSchema>;
export type FightRecordFact = z.infer<typeof fightRecordFactSchema>;
export type ProfileHistoryRow = z.infer<typeof profileHistoryRowSchema>;
export type ProfileHistoryPage = z.infer<typeof profileHistoryPageSchema>;
export type ClassifiedFightResult = {
    result: (typeof profileResultValues)[number];
    counted: boolean;
    fieldSize: number;
    placement: number | null;
};

export type ResultEvidenceSummary = z.infer<typeof resultEvidenceSummarySchema>;
