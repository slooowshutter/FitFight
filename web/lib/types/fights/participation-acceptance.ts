import { z } from "zod";
import { joiningFightRowSchema } from "./joinable-fight";

export const acceptingFightSchema = joiningFightRowSchema.extend({ series_id: z.string().uuid().nullable() });
export const acceptingInviteSchema = z.object({
    id: z.string().uuid(), fight_id: z.string().uuid(), invited_user_id: z.string().uuid().nullable(),
    expires_at: z.coerce.date(), revoked_at: z.coerce.date().nullable(),
});
export type AcceptingFight = z.infer<typeof acceptingFightSchema>;
export type AcceptingInvite = z.infer<typeof acceptingInviteSchema>;
