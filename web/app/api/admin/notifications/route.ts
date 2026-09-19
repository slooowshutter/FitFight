import { createHash, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { sendApnsAlert } from "@/lib/apns/apns-client";
import { readApnsEnvironment } from "@/lib/apns/apns-config";
import { ApiError, ERROR_CODES, apiRoute, json, readJson } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { lookupProfileByHandle } from "@/lib/supabase/queries/create-invite-supabase-query";
import {
    decryptInstallationToken,
    readActiveDeviceInstallations,
} from "@/lib/supabase/queries/device-installations-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

export const POST = apiRoute(async (request) => {
    const secret = process.env.CRON_SECRET ?? process.env.FITFIGHT_CRON_SECRET;
    if (!secret) {
        throw new ApiError(503, ERROR_CODES.config, "Cron secret is not set");
    }
    const bearer = request.headers
        .get("authorization")
        ?.match(/^Bearer (\S+)$/i)?.[1];
    if (
        !bearer ||
        !timingSafeEqual(
            createHash("sha256").update(bearer).digest(),
            createHash("sha256").update(secret).digest(),
        )
    ) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Unauthorized");
    }

    const input = z
        .object({
            username: z.string().trim().min(1).max(31),
            message: z.string().trim().min(1).max(500),
        })
        .strict()
        .parse(await readJson(request, 8192));
    const environment = readApnsEnvironment();
    if (!environment) {
        throw new ApiError(503, ERROR_CODES.config, "APNs is not configured");
    }
    const profile = await lookupProfileByHandle(
        createAdminClient(),
        input.username,
    );
    const [installation] = await readActiveDeviceInstallations(
        profile.user_id,
        createDatabaseClient(),
    );
    if (!installation) {
        throw new ApiError(
            404,
            ERROR_CODES.not_found,
            "No active device for this username",
        );
    }
    const result = await sendApnsAlert({
        deviceToken: decryptInstallationToken(installation),
        environment: installation.apns_environment,
        topic: environment.topic,
        title: "FitFight",
        body: input.message,
        route: "/",
    });
    return json({
        accepted: result.httpStatus === 200,
        apns_http_status: result.httpStatus,
        apns_id: result.apnsId,
        reason: result.reason,
    });
});
