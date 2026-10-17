import { z } from "zod";
import { sharedIdentitySchema } from "@/lib/types/profiles/shared-profile";

export const profileSearchRequestSchema = z.object({
    q: z
        .string()
        .trim()
        .transform((value) => value.replace(/^@/, "").toLowerCase())
        .pipe(z.string().regex(/^[a-z0-9_]{2,30}$/, "Type at least 2 letters of a username")),
});
export const profileSearchSchema = z.object({
    people: z.array(sharedIdentitySchema),
});
export const profileSearchRowSchema = sharedIdentitySchema.extend({
    avatar_path: z.string().nullable(),
});

export type ProfileSearch = z.infer<typeof profileSearchSchema>;
