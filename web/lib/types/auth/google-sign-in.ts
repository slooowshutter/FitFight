import { z } from "zod";

export const googleIdentityRequestSchema = z
    .object({
        id_token: z.string().min(1).max(16_384),
        access_token: z.string().min(1).max(16_384),
        nonce: z.string().min(16).max(128),
    })
    .strict();

export const googleIdentityResponseSchema = z
    .object({
        linked: z.boolean(),
    })
    .strict();

export const googleIdTokenClaimsSchema = z.object({
    aud: z.union([z.string().min(1), z.string().min(1).array()]),
    azp: z.string().min(1).optional(),
    email: z.string().email(),
    email_verified: z.union([z.boolean(), z.literal("true"), z.literal("false")]),
    exp: z.number().int(),
    iat: z.number().int().optional(),
    iss: z.string().min(1),
    nonce: z.string().min(1).optional(),
    sub: z.string().min(1).max(255),
});

export type GoogleIdentityRequest = z.infer<typeof googleIdentityRequestSchema>;
export type GoogleIdentityResponse = z.infer<
    typeof googleIdentityResponseSchema
>;
export type GoogleIdTokenClaims = z.infer<typeof googleIdTokenClaimsSchema>;
