import { z } from "zod";
import { fightVisibilityValues } from "./fight-visibility";
import { fightJoinStartSchema } from "./join-start";
import { fightStateValues, fightMemberStateValues } from "./membership-decision";

export const fightVisibilitySchema = z.enum(fightVisibilityValues);

export const joinableFightSummarySchema = z.object({
    fightId: z.string().uuid(),
    seriesId: z.string().uuid(),
    name: z.string(),
    joinCode: z.string(),
    ownerHandle: z.string(),
    actionText: z.string().nullable(),
    startsAt: z.string(),
    endsAt: z.string(),
    memberCount: z.number().int().nonnegative(),
    recurring: z.boolean(),
    alreadyMember: z.boolean(),
    canJoinNext: z.boolean(),
});

export const joinableFightListResponseSchema = z.object({
    fights: z.array(joinableFightSummarySchema),
});

export const joinFightRequestSchema = z
    .object({
        code: z.string().min(1).max(16).optional(),
        fightId: z.string().uuid().optional(),
        start: fightJoinStartSchema.default("now"),
    })
    .superRefine((value, ctx) => {
        if (!value.code && !value.fightId) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "code or fightId is required",
            });
        }
    });

export const leaveFightRequestSchema = z.object({
    fightId: z.string().uuid(),
});

export type FightVisibility = z.infer<typeof fightVisibilitySchema>;
export type JoinableFightSummary = z.infer<typeof joinableFightSummarySchema>;
export type JoinableFightListResponse = z.infer<
    typeof joinableFightListResponseSchema
>;
export type JoinFightRequest = z.infer<typeof joinFightRequestSchema>;
export type LeaveFightRequest = z.infer<typeof leaveFightRequestSchema>;

export const joiningFightRowSchema = z.object({
    id: z.string().uuid(), state: z.enum(fightStateValues), starts_at: z.coerce.date(), ends_at: z.coerce.date(),
    time_zone: z.string(), series_id: z.string().uuid(),
});
export const joiningSeriesRowSchema = z.object({
    id: z.string().uuid(), visibility: fightVisibilitySchema, recurring: z.boolean(),
    paused_at: z.coerce.date().nullable(), current_fight_id: z.string().uuid().nullable(), join_code: z.string().nullable(),
});
export const joiningMemberRowSchema = z.object({ state: z.enum(fightMemberStateValues) });
