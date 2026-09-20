import { createSign, generateKeyPairSync } from "node:crypto";
import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError } from "@/lib/http";
import {
    hashedGoogleNonce,
    resetGoogleSigningKeysForTests,
    verifyGoogleIdToken,
} from "./google-id-token";
import { googleOAuthClients } from "./google-clients";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
});
const jwk = publicKey.export({ format: "jwk" });
const kid = "fitfight-google-test";
const staging = googleOAuthClients["zstzbfocunthczzubggz.supabase.co"];
const projectURL = "https://zstzbfocunthczzubggz.supabase.co";

function signToken(
    claims: Record<string, unknown>,
    header: Record<string, unknown> = { alg: "RS256", kid, typ: "JWT" },
): string {
    const encodedHeader = Buffer.from(JSON.stringify(header)).toString(
        "base64url",
    );
    const encodedPayload = Buffer.from(JSON.stringify(claims)).toString(
        "base64url",
    );
    const signer = createSign("RSA-SHA256");
    signer.update(`${encodedHeader}.${encodedPayload}`);
    signer.end();
    return `${encodedHeader}.${encodedPayload}.${signer.sign(privateKey).toString("base64url")}`;
}

test("Google ID tokens must be signed, audience-bound, verified, and nonce-matched", async () => {
    resetGoogleSigningKeysForTests();
    const now = Math.floor(Date.now() / 1000);
    const nonce = "abcDEF0123456789-_xyzXYZ01234567";
    const valid = signToken({
        aud: staging.webClientID,
        azp: staging.iosClientID,
        email: "marc@marclamy.com",
        email_verified: true,
        exp: now + 300,
        iat: now,
        iss: "https://accounts.google.com",
        nonce: hashedGoogleNonce(nonce),
        sub: "google-subject",
    });
    const claims = await verifyGoogleIdToken(valid, nonce, {
        projectURL,
        keys: [{ ...jwk, kid, alg: "RS256", kty: "RSA" }],
    });
    assert.equal(claims.sub, "google-subject");
    assert.equal(claims.email, "marc@marclamy.com");

    await assert.rejects(
        verifyGoogleIdToken(valid, "other-nonce-0123456789abcdef", {
            projectURL,
            keys: [{ ...jwk, kid, alg: "RS256", kty: "RSA" }],
        }),
        (error: unknown) =>
            error instanceof ApiError && error.code === "unauthorized",
    );
    await assert.rejects(
        verifyGoogleIdToken(
            signToken({
                aud: staging.webClientID,
                email: "marc@marclamy.com",
                email_verified: false,
                exp: now + 300,
                iss: "https://accounts.google.com",
                nonce: hashedGoogleNonce(nonce),
                sub: "google-subject",
            }),
            nonce,
            {
                projectURL,
                keys: [{ ...jwk, kid, alg: "RS256", kty: "RSA" }],
            },
        ),
        (error: unknown) =>
            error instanceof ApiError && error.code === "unauthorized",
    );
});
