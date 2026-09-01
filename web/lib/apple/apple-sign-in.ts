import {
  createCipheriv,
  createDecipheriv,
  createPrivateKey,
  randomBytes,
  sign,
} from "node:crypto";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
  appleIdentityTokenClaimsSchema,
  appleSignInEnvironmentSchema,
  appleTokenResponseSchema,
  type AppleSignInEnvironment,
  type EncryptedAppleRefreshToken,
} from "@/lib/types/apple/apple-sign-in";

function appleSignInEnvironment(): AppleSignInEnvironment {
  const parsed = appleSignInEnvironmentSchema.safeParse({
    clientId: process.env.APPLE_SIGN_IN_CLIENT_ID ?? "com.fitfight.mvp",
    keyId: process.env.APPLE_SIGN_IN_KEY_ID,
    privateKey: process.env.APPLE_SIGN_IN_PRIVATE_KEY?.replace(/\\n/g, "\n"),
    teamId: process.env.APPLE_SIGN_IN_TEAM_ID ?? process.env.APPLE_TEAM_ID,
    tokenEncryptionKey: process.env.APPLE_SIGN_IN_TOKEN_ENCRYPTION_KEY,
  });
  if (!parsed.success) {
    throw new ApiError(500, ERROR_CODES.config, "Sign in with Apple server credentials are missing");
  }
  return parsed.data;
}

export function encryptAppleRefreshToken(refreshToken: string): EncryptedAppleRefreshToken {
  const environment = appleSignInEnvironment();
  const encryptionIv = randomBytes(12);
  const cipher = createCipheriv(
    "aes-256-gcm",
    Buffer.from(environment.tokenEncryptionKey, "base64"),
    encryptionIv,
  );
  const encrypted = Buffer.concat([cipher.update(refreshToken, "utf8"), cipher.final()]);
  return {
    encryptedRefreshToken: encrypted.toString("base64"),
    encryptionIv: encryptionIv.toString("base64"),
    encryptionTag: cipher.getAuthTag().toString("base64"),
  };
}

export function decryptAppleRefreshToken(token: EncryptedAppleRefreshToken): string {
  const environment = appleSignInEnvironment();
  try {
    const decipher = createDecipheriv(
      "aes-256-gcm",
      Buffer.from(environment.tokenEncryptionKey, "base64"),
      Buffer.from(token.encryptionIv, "base64"),
    );
    decipher.setAuthTag(Buffer.from(token.encryptionTag, "base64"));
    return Buffer.concat([
      decipher.update(Buffer.from(token.encryptedRefreshToken, "base64")),
      decipher.final(),
    ]).toString("utf8");
  } catch {
    throw new ApiError(500, ERROR_CODES.db_error, "Stored Apple authorization could not be read");
  }
}

function appleClientSecret(environment: AppleSignInEnvironment): string {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({
    alg: "ES256",
    kid: environment.keyId,
    typ: "JWT",
  })).toString("base64url");
  const claims = Buffer.from(JSON.stringify({
    aud: "https://appleid.apple.com",
    exp: now + 300,
    iat: now,
    iss: environment.teamId,
    sub: environment.clientId,
  })).toString("base64url");
  const unsigned = `${header}.${claims}`;
  const signature = sign("sha256", Buffer.from(unsigned), {
    dsaEncoding: "ieee-p1363",
    key: createPrivateKey(environment.privateKey),
  }).toString("base64url");
  return `${unsigned}.${signature}`;
}

export async function exchangeAppleAuthorizationCode(
  authorizationCode: string,
  request: typeof fetch = fetch,
): Promise<{ refreshToken: string; subject: string }> {
  const environment = appleSignInEnvironment();
  const response = await request("https://appleid.apple.com/auth/token", {
    body: new URLSearchParams({
      client_id: environment.clientId,
      client_secret: appleClientSecret(environment),
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    method: "POST",
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) {
    throw new ApiError(502, ERROR_CODES.internal, "Apple authorization could not be saved");
  }
  const parsed = appleTokenResponseSchema.safeParse(await response.json());
  if (!parsed.success) {
    throw new ApiError(502, ERROR_CODES.internal, "Apple returned an invalid token response");
  }
  const tokenParts = parsed.data.id_token.split(".");
  if (tokenParts.length !== 3 || !tokenParts[1]) {
    throw new ApiError(502, ERROR_CODES.internal, "Apple returned an invalid identity token");
  }
  let claims: unknown;
  try {
    claims = JSON.parse(Buffer.from(tokenParts[1], "base64url").toString("utf8")) as unknown;
  } catch {
    throw new ApiError(502, ERROR_CODES.internal, "Apple returned an invalid identity token");
  }
  const parsedClaims = appleIdentityTokenClaimsSchema.safeParse(claims);
  if (!parsedClaims.success) {
    throw new ApiError(502, ERROR_CODES.internal, "Apple returned an invalid identity token");
  }
  return {
    refreshToken: parsed.data.refresh_token,
    subject: parsedClaims.data.sub,
  };
}

export async function revokeAppleRefreshToken(
  refreshToken: string,
  request: typeof fetch = fetch,
): Promise<void> {
  const environment = appleSignInEnvironment();
  const response = await request("https://appleid.apple.com/auth/revoke", {
    body: new URLSearchParams({
      client_id: environment.clientId,
      client_secret: appleClientSecret(environment),
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    method: "POST",
    signal: AbortSignal.timeout(3_000),
  });
  if (!response.ok) {
    throw new ApiError(502, ERROR_CODES.internal, "Apple authorization could not be revoked");
  }
}
