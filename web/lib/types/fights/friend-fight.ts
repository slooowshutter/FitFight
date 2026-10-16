import { z } from "zod";

/** Every friend round runs [1st 00:00, next 1st 00:00) in this zone, so all of them end at one moment. */
export const FRIEND_FIGHT_TIME_ZONE = "UTC";
export const FRIEND_FIGHT_NAME = "Friends";

export const friendFightPairSchema = z.object({
    user_low: z.string().uuid(),
    user_high: z.string().uuid(),
    requester_id: z.string().uuid(),
    series_id: z.string().uuid().nullable(),
    live_fight_id: z.string().uuid().nullable(),
});

export const friendFightMemberSchema = z.object({
    user_id: z.string().uuid(),
    selected_source_id: z.string().uuid(),
});

export type FriendFightPair = z.infer<typeof friendFightPairSchema>;
export type FriendFightMember = z.infer<typeof friendFightMemberSchema>;
