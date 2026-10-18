import { z } from "zod";

/** Monthly friend rounds run [1st 00:00, next 1st 00:00) in this zone, so all of them end at one moment. */
export const FRIEND_FIGHT_TIME_ZONE = "UTC";
export const FRIEND_FIGHT_NAME = "Friends";
/** A friend series with this `duration_seconds` runs weekly rounds; any other value runs calendar months. */
export const FRIEND_FIGHT_WEEK_SECONDS = 7 * 86_400;

/** How long a friend round lasts: the calendar month (the default) or 7 days. Either friend can change it. */
export const friendRoundLengthValues = ["month", "week"] as const;
export const friendRoundLengthSchema = z.enum(friendRoundLengthValues);

export const friendFightPairSchema = z.object({
    user_low: z.string().uuid(),
    user_high: z.string().uuid(),
    requester_id: z.string().uuid(),
    series_id: z.string().uuid().nullable(),
    live_fight_id: z.string().uuid().nullable(),
    duration_seconds: z.number().int().nullable(),
    last_ends_at: z.coerce.date().nullable(),
});

export const friendFightMemberSchema = z.object({
    user_id: z.string().uuid(),
    selected_source_id: z.string().uuid(),
});

export type FriendRoundLength = z.infer<typeof friendRoundLengthSchema>;
export type FriendFightPair = z.infer<typeof friendFightPairSchema>;
export type FriendFightMember = z.infer<typeof friendFightMemberSchema>;
