import { z } from "zod";
import { fightVisibilitySchema } from "./joinable-fight";
import { timeZoneSchema } from "@/lib/types/time/time-zone";

const dateTime = z
    .string()
    .refine(
        (value) => Number.isFinite(Date.parse(value)),
        "must be a date-time",
    );

export const createFightSchema = z
    .object({
        name: z.string().trim().max(120).optional(),
        startsAt: dateTime,
        endsAt: dateTime,
        timeZone: timeZoneSchema,
        outcomeRule: z.enum(["highest_total", "proportional", "hit_your_goal"]),
        goalPolicy: z.enum(["shared", "personal"]).default("shared"),
        defaultGoalValue: z.number().optional(),
        stakeKind: z.enum(["bragging", "money", "action"]),
        stakeMinor: z.number().int().min(0).optional(),
        currency: z.string().default("USD"),
        actionText: z.string().trim().max(120).optional(),
        inviteHandles: z.array(z.string()).optional(),
        start: z.enum(["now", "scheduled"]).default("now"),
        metric: z.literal("steps").optional(),
        visibility: fightVisibilitySchema.default("invite_only"),
        recurring: z.boolean().default(true),
    })
    .superRefine((value, ctx) => {
        const starts = Date.parse(value.startsAt);
        const ends = Date.parse(value.endsAt);
        if (!Number.isFinite(starts) || !Number.isFinite(ends)) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "startsAt and endsAt must be dates",
            });
            return;
        }
        if (ends <= starts) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "endsAt must be after startsAt",
            });
        }
    });

export type CreateFightInput = z.infer<typeof createFightSchema>;
