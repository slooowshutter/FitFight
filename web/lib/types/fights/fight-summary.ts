import { z } from "zod";
import { fightStateValues } from "./membership-decision";

/** What create, join, accept, decline, leave and cancel answer (`fightSummary` on the server). */
export const fightSummaryResponseSchema = z.object({
    id: z.string().uuid(),
    state: z.enum(fightStateValues),
});
