import { z } from "zod";
import { fightStateValues, fightMemberStateValues } from "./membership-decision";

export const departureFightSchema = z.object({
    id: z.string().uuid(), owner_id: z.string().uuid(), state: z.enum(fightStateValues), series_id: z.string().uuid().nullable(),
});
export const departureMemberSchema = z.object({ fight_id: z.string().uuid(), state: z.enum(fightMemberStateValues) });
