import { createHash, createPublicKey, createVerify } from "node:crypto";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
    googleIdTokenClaimsSchema,
    type GoogleIdTokenClaims,
} from "@/lib/types/auth/google-sign-in";
import { googleOAuthClientsForProject } from "./google-clients";

const GOOGLE_ISSUERS = new Set([
    "https://accounts.google.com",
    "accounts.google.com",
]);
const JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const JWKS_TTL_MS = 60 * 60 * 1000;

type JsonWebKey = {
    kid?: string;
    kty: string;
    n?: string;
    e?: string;
    alg?: string;
    use?: string;
};

let cachedKeys: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

export function hashedGoogleNonce(nonce: string): string {
    return createHash("sha256").update(nonce, "utf8").digest("hex");
}

export function emailFromGoogleClaims(claims: GoogleIdTokenClaims): string {
    return claims.email.trim().toLowerCase();
}

export function googleEmailIsVerified(claims: GoogleIdTokenClaims): boolean {
    return claims.email_verified === true || claims.email_verified === "true";
}

function audiences(value: GoogleIdTokenClaims["aud"]): string[] {
    return Array.isArray(value) ? value : [value];
}

async function googleSigningKeys(
    request: typeof fetch,
    now: number,
    injected?: JsonWebKey[],
): Promise<JsonWebKey[]> {
    if (injected) return injected;
    if (cachedKeys && now - cachedKeys.fetchedAt < JWKS_TTL_MS) {
        return cachedKeys.keys;
    }
    const response = await request(JWKS_URL, {
        signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Google signing keys could not be loaded",
        );
    }
    const body = (await response.json()) as { keys?: JsonWebKey[] };
    if (!Array.isArray(body.keys) || body.keys.length === 0) {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Google signing keys could not be loaded",
        );
    }
    cachedKeys = { keys: body.keys, fetchedAt: now };
    return body.keys;
}

function decodeJwtPart(part: string): unknown {
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

function verifyRs256(signed: string, signature: string, key: JsonWebKey): boolean {
    const publicKey = createPublicKey({
        key,
        format: "jwk",
    });
    const verifier = createVerify("RSA-SHA256");
    verifier.update(signed);
    verifier.end();
    return verifier.verify(publicKey, Buffer.from(signature, "base64url"));
}

export async function verifyGoogleIdToken(
    idToken: string,
    nonce: string,
    options: {
        projectURL?: string;
        now?: number;
        keys?: JsonWebKey[];
        request?: typeof fetch;
    } = {},
): Promise<GoogleIdTokenClaims> {
    const parts = idToken.split(".");
    if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    let header: { kid?: string; alg?: string };
    try {
        header = decodeJwtPart(parts[0]) as { kid?: string; alg?: string };
    } catch {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    if (header.alg !== "RS256") {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    const now = options.now ?? Date.now();
    const keys = await googleSigningKeys(
        options.request ?? fetch,
        now,
        options.keys,
    );
    const key = header.kid
        ? keys.find((candidate) => candidate.kid === header.kid)
        : keys[0];
    if (!key || !verifyRs256(`${parts[0]}.${parts[1]}`, parts[2], key)) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    let claims: GoogleIdTokenClaims;
    try {
        claims = googleIdTokenClaimsSchema.parse(decodeJwtPart(parts[1]));
    } catch {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    if (!GOOGLE_ISSUERS.has(claims.iss) || claims.exp * 1000 <= now) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    if (!googleEmailIsVerified(claims)) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    const projectURL =
        options.projectURL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
    const clients = googleOAuthClientsForProject(projectURL);
    if (!clients) {
        throw new ApiError(
            500,
            ERROR_CODES.config,
            "Google sign-in is not configured for this database",
        );
    }
    const allowed = new Set<string>([clients.webClientID, clients.iosClientID]);
    if (!audiences(claims.aud).some((audience) => allowed.has(audience))) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    if (claims.azp && !allowed.has(claims.azp)) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    if (claims.nonce !== hashedGoogleNonce(nonce)) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    return claims;
}

export function resetGoogleSigningKeysForTests(): void {
    cachedKeys = null;
}
