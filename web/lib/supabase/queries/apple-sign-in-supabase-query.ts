import type { Sql } from "postgres";
import {
  decryptAppleRefreshToken,
  encryptAppleRefreshToken,
  exchangeAppleAuthorizationCode,
} from "@/lib/apple/apple-sign-in";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  appleIdentityRowSchema,
  appleRefreshTokenRowSchema,
} from "@/lib/types/apple/apple-sign-in";

export async function storeAppleAuthorization(
  userId: string,
  authorizationCode: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  const token = await exchangeAppleAuthorizationCode(authorizationCode);
  const identityRows = await database`
    select provider_id
    from auth.identities
    where user_id = ${userId} and provider = 'apple'
  `;
  const identity = appleIdentityRowSchema.safeParse(identityRows[0]);
  if (!identity.success || identity.data.provider_id !== token.subject) {
    throw new ApiError(403, ERROR_CODES.forbidden, "Apple authorization does not match this account");
  }
  const encrypted = encryptAppleRefreshToken(token.refreshToken);
  await database`
    insert into private.apple_sign_in_tokens (
      user_id,
      apple_subject,
      encrypted_refresh_token,
      encryption_iv,
      encryption_tag,
      updated_at
    ) values (
      ${userId},
      ${token.subject},
      ${encrypted.encryptedRefreshToken},
      ${encrypted.encryptionIv},
      ${encrypted.encryptionTag},
      now()
    )
    on conflict (user_id) do update
    set apple_subject = excluded.apple_subject,
        encrypted_refresh_token = excluded.encrypted_refresh_token,
        encryption_iv = excluded.encryption_iv,
        encryption_tag = excluded.encryption_tag,
        updated_at = now()
  `;
}

export async function readStoredAppleRefreshToken(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<string | null> {
  const rows = await database`
    select encrypted_refresh_token, encryption_iv, encryption_tag
    from private.apple_sign_in_tokens
    where user_id = ${userId}
  `;
  if (!rows[0]) {
    return null;
  }
  const token = appleRefreshTokenRowSchema.safeParse(rows[0]);
  if (!token.success) {
    throw new ApiError(500, ERROR_CODES.db_error, "Stored Apple authorization is invalid");
  }
  return decryptAppleRefreshToken({
    encryptedRefreshToken: token.data.encrypted_refresh_token,
    encryptionIv: token.data.encryption_iv,
    encryptionTag: token.data.encryption_tag,
  });
}
