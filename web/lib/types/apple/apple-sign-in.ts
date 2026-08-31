import { z } from "zod";

export const appleAuthorizationRequestSchema = z.object({
  authorization_code: z.string().min(1).max(2048),
}).strict();

export const appleSignInEnvironmentSchema = z.object({
  clientId: z.string().min(1).max(255),
  keyId: z.string().regex(/^[A-Z0-9]{10}$/),
  privateKey: z.string().includes("BEGIN PRIVATE KEY"),
  teamId: z.string().regex(/^[A-Z0-9]{10}$/),
  tokenEncryptionKey: z.string().base64().refine(
    (value) => Buffer.from(value, "base64").byteLength === 32,
    "must be a base64-encoded 32-byte key",
  ),
});

export const appleTokenResponseSchema = z.object({
  access_token: z.string().min(1),
  expires_in: z.number().int().positive(),
  id_token: z.string().min(1),
  refresh_token: z.string().min(1),
  token_type: z.string().min(1),
});

export const appleIdentityTokenClaimsSchema = z.object({
  sub: z.string().min(1),
});

export const appleIdentityRowSchema = z.object({
  provider_id: z.string().min(1),
});

export const encryptedAppleRefreshTokenSchema = z.object({
  encryptedRefreshToken: z.string().min(1),
  encryptionIv: z.string().min(1),
  encryptionTag: z.string().min(1),
});

export const appleRefreshTokenRowSchema = z.object({
  encrypted_refresh_token: z.string().min(1),
  encryption_iv: z.string().min(1),
  encryption_tag: z.string().min(1),
});

export type AppleSignInEnvironment = z.infer<typeof appleSignInEnvironmentSchema>;
export type EncryptedAppleRefreshToken = z.infer<typeof encryptedAppleRefreshTokenSchema>;
