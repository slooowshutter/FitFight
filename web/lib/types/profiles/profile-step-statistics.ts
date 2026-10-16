import { z } from "zod";

export const profileActivityLevelValues = ["couch", "warming_up", "moving", "active", "ripped"] as const;
export const profileActivityMinimumSteps = [0, 2_000, 4_000, 6_000, 8_000] as const;

const daySchema = z.string().date();

export const profileStatisticsContextSchema = z.object({
    today: daySchema,
    time_zone: z.string(),
});

export const profileStepStatisticsSchema = z.object({
    scope_days: z.union([z.literal(7), z.literal(30)]).nullable(),
    from: daySchema.nullable(),
    through: daySchema,
    time_zone: z.string(),
    recorded_days: z.number().int().nonnegative(),
    unknown_days: z.number().int().nonnegative(),
    total_steps: z.number().nonnegative(),
    average_steps: z.number().nonnegative().nullable(),
    best_day: z.object({ day: daySchema, steps: z.number().nonnegative() }).nullable(),
    week: z.object({
        starts_on: daySchema,
        elapsed_days: z.number().int().min(0).max(6),
        recorded_days: z.number().int().min(0).max(6),
        total_steps: z.number().nonnegative(),
        average_steps: z.number().nonnegative().nullable(),
    }),
    levels: z.array(z.object({
        level: z.enum(profileActivityLevelValues),
        minimum_steps: z.number().int().nonnegative(),
        days: z.number().int().nonnegative(),
        share: z.number().min(0).max(1).nullable(),
        longest_streak: z.number().int().nonnegative(),
        current_streak: z.number().int().nonnegative().nullable(),
    })).length(5),
});

/** Owners also get their best run and the 13 days before today; friends get only the current run. */
export const tenKStreakSchema = z.object({
    goal: z.number().int().positive(),
    current: z.number().int().nonnegative(),
    today_counted: z.boolean(),
    best: z.object({ days: z.number().int().positive(), from: daySchema, through: daySchema }).nullable(),
    recent: z.array(z.object({ day: daySchema, steps: z.number().nonnegative().nullable() })).length(13).nullable(),
});

export const stepTotalsSchema = z.object({
    recorded_days: z.number().int().nonnegative(),
    total_steps: z.number().nonnegative(),
    average_steps: z.number().nonnegative().nullable(),
    best_day_steps: z.number().nonnegative().nullable(),
    ten_k_days: z.number().int().nonnegative(),
});

/** Complete days from the day two people became friends through yesterday; `days` is 0 on that first day. */
export const friendComparisonSchema = z.object({
    since: daySchema,
    days: z.number().int().nonnegative(),
    you: stepTotalsSchema,
    them: stepTotalsSchema,
});

export const profileStartDaysRowSchema = z.object({ member_since: daySchema, friends_since: daySchema.nullable() });

export type ProfileStatisticsContext = z.infer<typeof profileStatisticsContextSchema>;
export type ProfileStepStatistics = z.infer<typeof profileStepStatisticsSchema>;
export type TenKStreak = z.infer<typeof tenKStreakSchema>;
export type StepTotals = z.infer<typeof stepTotalsSchema>;
export type FriendComparison = z.infer<typeof friendComparisonSchema>;
