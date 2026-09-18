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

export type ProfileStatisticsContext = z.infer<typeof profileStatisticsContextSchema>;
export type ProfileStepStatistics = z.infer<typeof profileStepStatisticsSchema>;
