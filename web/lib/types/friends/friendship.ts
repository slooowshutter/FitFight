import { z } from "zod";
import { friendshipStateValues, sharedIdentitySchema } from "@/lib/types/profiles/shared-profile";

export const friendshipActionValues = ["request", "accept", "decline", "remove"] as const;
export const friendshipResponseSchema = z.object({ friendship: z.enum(friendshipStateValues) });
export const respondToFriendRequestSchema = z.object({ action: z.enum(["accept", "decline"]) }).strict();
export const friendsQuerySchema = z.object({
    kind: z.enum(["accepted", "incoming", "outgoing"]).default("accepted"),
    cursor: z.string().uuid().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
});
export const friendsPageSchema = z.object({
    people: z.array(sharedIdentitySchema),
    next_cursor: z.string().uuid().nullable(),
    incoming_count: z.number().int().nonnegative(),
});
export const friendshipRowSchema = z.object({
    requester_id: z.string().uuid(),
    state: z.enum(["pending", "accepted"]),
});

export const profileFriendListRowSchema = sharedIdentitySchema.extend(friendshipRowSchema.shape).extend({ avatar_path: z.string().nullable() });
export type ProfileFriendListRow = z.infer<typeof profileFriendListRowSchema>;

export type FriendshipAction = (typeof friendshipActionValues)[number];
export type FriendshipResponse = z.infer<typeof friendshipResponseSchema>;
export type FriendsQuery = z.infer<typeof friendsQuerySchema>;
export type FriendsPage = z.infer<typeof friendsPageSchema>;
