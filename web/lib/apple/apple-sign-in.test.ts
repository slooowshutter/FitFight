import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes } from "node:crypto";
import { test } from "node:test";
import {
  decryptAppleRefreshToken,
  encryptAppleRefreshToken,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
} from "./apple-sign-in";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
process.env.APPLE_SIGN_IN_CLIENT_ID = "com.fitfight.mvp";
process.env.APPLE_SIGN_IN_KEY_ID = "ABCDEFGHIJ";
process.env.APPLE_SIGN_IN_PRIVATE_KEY = privateKey.export({
  format: "pem",
  type: "pkcs8",
}).toString();
process.env.APPLE_SIGN_IN_TEAM_ID = "C92DPD8ME2";
process.env.APPLE_SIGN_IN_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");

test("Apple authorization codes are exchanged with a signed native-app request", async () => {
  let requestBody = "";
  const request = (async (input: URL | RequestInfo, init?: RequestInit) => {
    assert.equal(input.toString(), "https://appleid.apple.com/auth/token");
    requestBody = init?.body?.toString() ?? "";
    const payload = Buffer.from(JSON.stringify({ sub: "apple-subject" })).toString("base64url");
    return new Response(JSON.stringify({
      access_token: "apple-access-token",
      expires_in: 3600,
      id_token: `header.${payload}.signature`,
      refresh_token: "apple-refresh-token",
      token_type: "Bearer",
    }), { status: 200 });
  }) as typeof fetch;

  const token = await exchangeAppleAuthorizationCode("authorization-code", request);
  const body = new URLSearchParams(requestBody);

  assert.deepEqual(token, {
    refreshToken: "apple-refresh-token",
    subject: "apple-subject",
  });
  assert.equal(body.get("client_id"), "com.fitfight.mvp");
  assert.equal(body.get("code"), "authorization-code");
  assert.equal(body.get("grant_type"), "authorization_code");
  assert.equal(body.get("client_secret")?.split(".").length, 3);
  assert.equal(body.has("redirect_uri"), false);
});

test("Apple refresh tokens are encrypted at rest and revoked as refresh tokens", async () => {
  const encrypted = encryptAppleRefreshToken("apple-refresh-token");
  assert.notEqual(encrypted.encryptedRefreshToken, "apple-refresh-token");
  assert.equal(decryptAppleRefreshToken(encrypted), "apple-refresh-token");

  let requestBody = "";
  const request = (async (input: URL | RequestInfo, init?: RequestInit) => {
    assert.equal(input.toString(), "https://appleid.apple.com/auth/revoke");
    requestBody = init?.body?.toString() ?? "";
    return new Response(null, { status: 200 });
  }) as typeof fetch;

  await revokeAppleRefreshToken("apple-refresh-token", request);
  const body = new URLSearchParams(requestBody);
  assert.equal(body.get("token"), "apple-refresh-token");
  assert.equal(body.get("token_type_hint"), "refresh_token");
});
