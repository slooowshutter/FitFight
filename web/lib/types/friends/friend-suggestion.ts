import { z } from "zod";
import { sharedIdentitySchema } from "@/lib/types/profiles/shared-profile";

export const friendSuggestionSchema = sharedIdentitySchema.extend({
    shared_fights: z.number().int().positive(),
});
export const friendSuggestionsSchema = z.object({
    people: z.array(friendSuggestionSchema),
});
export const friendSuggestionRowSchema = friendSuggestionSchema.extend({
    avatar_path: z.string().nullable(),
});

export type FriendSuggestion = z.infer<typeof friendSuggestionSchema>;
export type FriendSuggestions = z.infer<typeof friendSuggestionsSchema>;
export type FriendSuggestionRow = z.infer<typeof friendSuggestionRowSchema>;
