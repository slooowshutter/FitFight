import { z } from "zod";
import { fightStateValues, fightMemberStateValues } from "./membership-decision";

export const joinableFightListFightSchema = z.object({
    id: z.string().uuid(),
    state: z.enum(fightStateValues),
    starts_at: z.string().datetime({ offset: true }),
    ends_at: z.string().datetime({ offset: true }),
    time_zone: z.string(),
    action_text: z.string().nullable(),
    roster: z.tuple([z.object({ count: z.number().int().nonnegative() })]),
    membership: z.array(z.object({ user_id: z.string().uuid(), state: z.enum(fightMemberStateValues) })).max(1),
});

export const joinableFightListSeriesSchema = z.object({
    id: z.string().uuid(),
    name: z.string(),
    join_code: z.string().nullable(),
    recurring: z.boolean(),
    paused_at: z.string().nullable(),
    owner: z.object({ handle: z.string() }).nullable(),
    fight: joinableFightListFightSchema.nullable(),
});

export type JoinableFightListFight = z.infer<
    typeof joinableFightListFightSchema
>;
export type JoinableFightListSeries = z.infer<
    typeof joinableFightListSeriesSchema
>;
