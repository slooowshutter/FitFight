import { connect, type ClientHttp2Session } from "node:http2";
import { readApnsEnvironment } from "./apns-config";
import { getApnsProviderToken } from "./apns-jwt";

import type { ApnsSendInput, ApnsSendResult } from "@/lib/types/notifications/apns";

function apnsHost(environment: "sandbox" | "production"): string {
    return environment === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com";
}

function sendOnSession(
    session: ClientHttp2Session,
    input: ApnsSendInput,
    providerToken: string,
): Promise<ApnsSendResult> {
    return new Promise((resolve, reject) => {
        const payload = JSON.stringify({
            aps: {
                alert: { title: input.title, body: input.body },
                sound: "default",
                ...(input.threadId ? { "thread-id": input.threadId } : {}),
                ...(input.imageUrl ? { "mutable-content": 1 } : {}),
            },
            fitfight: { route: input.route, image_url: input.imageUrl },
        });
        const request = session.request({
            ":method": "POST",
            ":path": `/3/device/${input.deviceToken}`,
            authorization: `bearer ${providerToken}`,
            "apns-topic": input.topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
            ...(input.collapseId ? { "apns-collapse-id": input.collapseId } : {}),
            ...(input.expiresAt !== undefined ? { "apns-expiration": String(input.expiresAt) } : {}),
        });
        let responseStatus = 0;
        let reason: string | null = null;
        let apnsId: string | null = null;
        request.on("response", (headers) => {
            responseStatus = Number(headers[":status"] ?? 0);
            const headerReason = headers["apns-reason"];
            apnsId =
                typeof headers["apns-id"] === "string"
                    ? headers["apns-id"]
                    : null;
            reason = typeof headerReason === "string" ? headerReason : null;
        });
        const chunks: Buffer[] = [];
        request.on("data", (chunk: Buffer) => {
            chunks.push(chunk);
        });
        request.on("end", () => {
            if (!reason && chunks.length > 0) {
                try {
                    const parsed = JSON.parse(
                        Buffer.concat(chunks).toString("utf8"),
                    ) as { reason?: string };
                    reason = parsed.reason ?? reason;
                } catch {
                    // APNs sometimes returns an empty body on success.
                }
            }
            resolve({
                httpStatus: responseStatus,
                reason,
                apnsId,
                unregistered:
                    responseStatus === 410 ||
                    reason === "Unregistered" ||
                    reason === "BadDeviceToken" ||
                    reason === "DeviceTokenNotForTopic",
                retryLater:
                    responseStatus === 429 ||
                    responseStatus === 503 ||
                    (responseStatus === 403 &&
                        reason === "TooManyProviderTokenUpdates"),
                invalidProviderToken:
                    responseStatus === 403 && reason === "InvalidProviderToken",
            });
        });
        request.on("error", reject);
        request.end(payload);
    });
}

export async function sendApnsAlert(
    input: ApnsSendInput,
): Promise<ApnsSendResult> {
    const environment = readApnsEnvironment();
    if (!environment) {
        throw new Error("APNs credentials are not configured");
    }
    const providerToken = getApnsProviderToken(environment);
    const session = connect(apnsHost(input.environment));
    try {
        return await sendOnSession(session, input, providerToken);
    } finally {
        session.close();
    }
}
