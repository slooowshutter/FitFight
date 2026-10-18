import { createHmac, randomInt, timingSafeEqual } from "node:crypto";
import { openAes256Gcm, sealAes256Gcm } from "@/lib/crypto/aes-256-gcm";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
    claimWhoopState,
    readWhoopConnection,
    saveWhoopConnection,
    saveWhoopRecords,
    saveWhoopState,
    withLockedWhoopConnection,
} from "@/lib/supabase/queries/whoop-supabase-query";
import type { ActivityRawRecord } from "@/lib/types/activity/activity-pipeline";
import {
    whoopEnvironmentSchema,
    whoopPageSchema,
    whoopProfileSchema,
    whoopRecordFieldsSchema,
    whoopRecordSchema,
    whoopTokenErrorSchema,
    whoopTokenResponseSchema,
    whoopTokensSchema,
    type WhoopEnvironment,
    type WhoopTokenResponse,
} from "@/lib/types/whoop/whoop";

/** One WHOOP app serves staging and production. The ID is public: it is in every sign-in URL. */
const WHOOP_CLIENT_ID = "c371db54-9ac9-4bb7-8bbc-429c4a679fac";
const WHOOP_API = "https://api.prod.whoop.com/developer";
const WHOOP_AUTHORIZE_URL = "https://api.prod.whoop.com/oauth/oauth2/auth";
const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const WHOOP_SCOPES =
    "read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline";
/** Registered in the WHOOP Developer Dashboard. Keyed by Supabase project, like googleOAuthClients. */
const WHOOP_REDIRECT_URIS: Record<string, string> = {
    "zstzbfocunthczzubggz.supabase.co":
        "https://staging.fitfight.app/api/whoop/callback",
    "pvqntpteehdvhqyctwum.supabase.co":
        "https://fitfight.app/api/whoop/callback",
};
/** Everything WHOOP's API offers that changes over time. Body measurements are fetched separately. */
const WHOOP_COLLECTIONS = [
    { path: "/v2/cycle", type: "whoop_cycle", kind: "total" },
    { path: "/v2/recovery", type: "whoop_recovery", kind: "total" },
    { path: "/v2/activity/sleep", type: "whoop_sleep", kind: "total" },
    { path: "/v2/activity/workout", type: "whoop_workout", kind: "workout" },
] as const;
/** Each sync re-reads this much before the last one: cycles grow all day and WHOOP rescores sleep. */
const RESYNC_OVERLAP_MS = 3 * 24 * 60 * 60 * 1000;

function whoopEnvironment(): WhoopEnvironment {
    const parsed = whoopEnvironmentSchema.safeParse({
        clientSecret: process.env.WHOOP_CLIENT_SECRET,
        tokenEncryptionKey: process.env.WHOOP_TOKEN_ENCRYPTION_KEY,
    });
    if (!parsed.success) {
        throw new ApiError(
            500,
            ERROR_CODES.config,
            "WHOOP server credentials are missing",
        );
    }
    return parsed.data;
}

function whoopRedirectUri(): string {
    const host = new URL(
        process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://localhost",
    ).hostname;
    const uri = WHOOP_REDIRECT_URIS[host];
    if (!uri) {
        throw new ApiError(
            500,
            ERROR_CODES.config,
            "WHOOP is not configured for this environment",
        );
    }
    return uri;
}

export async function startWhoopConnection(userId: string): Promise<string> {
    // NOTE: WHOOP's docs require a self-generated state of exactly eight characters.
    const alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const state = Array.from(
        { length: 8 },
        () => alphabet[randomInt(alphabet.length)],
    ).join("");
    await saveWhoopState(userId, state);
    const url = new URL(WHOOP_AUTHORIZE_URL);
    url.search = new URLSearchParams({
        response_type: "code",
        client_id: WHOOP_CLIENT_ID,
        redirect_uri: whoopRedirectUri(),
        scope: WHOOP_SCOPES,
        state,
    }).toString();
    return url.toString();
}

/**
 * Finishes the sign-in WHOOP redirected back with: exchanges the code and saves the login on the
 * account that started it.
 */
export async function finishWhoopConnection(
    userId: string,
    code: string,
    state: string,
): Promise<void> {
    // NOTE: the state must belong to the signed-in caller. Otherwise someone could send their own
    // sign-in link to a friend and receive the friend's WHOOP data on their account.
    if (!(await claimWhoopState(userId, state))) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "This WHOOP sign-in expired. Try again.",
        );
    }
    const tokens = await requestWhoopTokens({ code });
    if (!tokens) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "WHOOP refused the sign-in. Try again.",
        );
    }
    const profile = whoopProfileSchema.parse(
        await whoopGet("/v2/user/profile/basic", tokens.access_token),
    );
    await saveWhoopConnection(
        userId,
        profile.user_id,
        sealWhoopTokens(tokens),
        new Date(Date.now() + tokens.expires_in * 1000),
    );
}

/**
 * Exchanges a sign-in code or a refresh token. Null only for `invalid_grant`: the person revoked
 * FitFight in WHOOP, or the code expired. Anything else, such as a wrong client secret (401), throws,
 * so a configuration mistake never signs everyone out.
 */
async function requestWhoopTokens(
    grant: { code: string } | { refresh_token: string },
): Promise<WhoopTokenResponse | null> {
    const environment = whoopEnvironment();
    const response = await fetch(WHOOP_TOKEN_URL, {
        method: "POST",
        signal: AbortSignal.timeout(30_000),
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
            ...("code" in grant
                ? {
                      grant_type: "authorization_code",
                      code: grant.code,
                      redirect_uri: whoopRedirectUri(),
                  }
                : {
                      grant_type: "refresh_token",
                      refresh_token: grant.refresh_token,
                      scope: "offline",
                  }),
            client_id: WHOOP_CLIENT_ID,
            client_secret: environment.clientSecret,
        }),
    });
    if (!response.ok) {
        const body: unknown = await response.json().catch(() => null);
        if (whoopTokenErrorSchema.safeParse(body).success) {
            return null;
        }
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            `WHOOP token request returned ${response.status}`,
        );
    }
    return whoopTokenResponseSchema.parse(await response.json());
}

function sealWhoopTokens(tokens: WhoopTokenResponse) {
    return sealAes256Gcm(
        JSON.stringify({
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
        }),
        whoopEnvironment().tokenEncryptionKey,
    );
}

/** GET from WHOOP's API. Waits out a 429 (100 requests a minute, 10,000 a day for the whole app). */
async function whoopGet(path: string, accessToken: string): Promise<unknown> {
    for (let attempt = 1; ; attempt += 1) {
        const response = await fetch(`${WHOOP_API}${path}`, {
            signal: AbortSignal.timeout(30_000),
            headers: { Authorization: `Bearer ${accessToken}` },
        });
        if (response.status === 429 && attempt < 4) {
            const resetSeconds =
                Number(response.headers.get("x-ratelimit-reset")) || 60;
            await new Promise((resolve) =>
                setTimeout(resolve, Math.min(resetSeconds, 60) * 1000),
            );
            continue;
        }
        if (!response.ok) {
            throw new ApiError(
                502,
                ERROR_CODES.internal,
                `WHOOP ${path} returned ${response.status}`,
            );
        }
        return response.json();
    }
}

/** WHOOP signs base64(HMAC-SHA256(timestamp + raw body)) with the app's client secret. */
export function verifyWhoopSignature(body: string, headers: Headers): void {
    const timestamp = headers.get("x-whoop-signature-timestamp") ?? "";
    const expected = createHmac("sha256", whoopEnvironment().clientSecret)
        .update(timestamp + body)
        .digest();
    const received = Buffer.from(
        headers.get("x-whoop-signature") ?? "",
        "base64",
    );
    if (
        !timestamp ||
        received.length !== expected.length ||
        !timingSafeEqual(received, expected)
    ) {
        throw new ApiError(
            401,
            ERROR_CODES.unauthorized,
            "Invalid WHOOP signature",
        );
    }
}

/**
 * Pulls everything WHOOP has for one person into private.activity_raw: their whole history the
 * first time, then the last few days. Records the outcome on the connection either way.
 */
export async function syncWhoopUser(userId: string): Promise<void> {
    const connection = await readWhoopConnection(userId);
    if (!connection?.tokens_ciphertext) {
        return;
    }
    const history = connection.history_synced_at === null;
    const since =
        history || !connection.last_synced_at
            ? null
            : new Date(connection.last_synced_at.getTime() - RESYNC_OVERLAP_MS);
    try {
        const accessToken = await withLockedWhoopConnection(
            userId,
            async (row, save) => {
                const environment = whoopEnvironment();
                if (
                    !row?.tokens_ciphertext ||
                    !row.tokens_iv ||
                    !row.tokens_tag ||
                    !row.access_token_expires_at
                ) {
                    throw new ApiError(
                        409,
                        ERROR_CODES.conflict,
                        "WHOOP is not connected",
                    );
                }
                const stored = whoopTokensSchema.parse(
                    JSON.parse(
                        openAes256Gcm(
                            {
                                ciphertext: row.tokens_ciphertext,
                                iv: row.tokens_iv,
                                tag: row.tokens_tag,
                            },
                            environment.tokenEncryptionKey,
                        ),
                    ),
                );
                // A full history pull takes a few minutes, so refresh unless the token has ten left.
                if (
                    row.access_token_expires_at.getTime() >
                    Date.now() + 10 * 60 * 1000
                ) {
                    return stored.access_token;
                }
                const refreshed = await requestWhoopTokens({
                    refresh_token: stored.refresh_token,
                });
                if (!refreshed) {
                    // Returning, not throwing, so forgetting the tokens commits.
                    await save(null, null);
                    return null;
                }
                await save(
                    sealWhoopTokens(refreshed),
                    new Date(Date.now() + refreshed.expires_in * 1000),
                );
                return refreshed.access_token;
            },
        );
        if (!accessToken) {
            throw new ApiError(
                409,
                ERROR_CODES.conflict,
                "WHOOP access was revoked",
            );
        }
        // Keyed by record: a page boundary that shifts mid-pull can return one record twice.
        const records = new Map<string, ActivityRawRecord>();
        for (const collection of WHOOP_COLLECTIONS) {
            let nextToken: string | null = null;
            do {
                const query = new URLSearchParams({ limit: "25" });
                if (since) query.set("start", since.toISOString());
                if (nextToken) query.set("nextToken", nextToken);
                const page = whoopPageSchema.parse(
                    await whoopGet(`${collection.path}?${query}`, accessToken),
                );
                for (const payload of page.records) {
                    const fields = whoopRecordFieldsSchema.parse(payload);
                    // Recoveries have no ID of their own. Key them by sleep, as WHOOP's recovery webhooks do.
                    const key = fields.id ?? fields.sleep_id;
                    if (key === undefined) {
                        throw new ApiError(
                            502,
                            ERROR_CODES.internal,
                            `WHOOP ${collection.type} has no id`,
                        );
                    }
                    records.set(`${collection.type}:${key}`, {
                        record_kind: collection.kind,
                        record_type: collection.type,
                        record_key: String(key),
                        starts_at: fields.start ?? null,
                        ends_at: fields.end ?? null,
                        time_zone: null,
                        payload,
                    });
                }
                nextToken = page.next_token || null;
            } while (nextToken);
        }
        records.set("whoop_body", {
            record_kind: "total",
            record_type: "whoop_body",
            record_key: "body",
            starts_at: null,
            ends_at: null,
            time_zone: null,
            payload: whoopRecordSchema.parse(
                await whoopGet("/v2/user/measurement/body", accessToken),
            ),
        });
        await saveWhoopRecords(userId, [...records.values()], {
            history,
            error: null,
        });
    } catch (error) {
        await saveWhoopRecords(userId, [], {
            history,
            error:
                error instanceof Error
                    ? error.message.slice(0, 300)
                    : "WHOOP sync failed",
        });
        throw error;
    }
}
