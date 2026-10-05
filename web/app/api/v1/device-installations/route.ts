import { after } from "next/server";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    registerDeviceInstallation,
    revokeDeviceInstallationForToken,
} from "@/lib/supabase/queries/device-installations-supabase-query";
import {
    registerDeviceInstallationRequestSchema,
    revokeDeviceInstallationRequestSchema,
} from "@/lib/types/notifications/device-installation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = registerDeviceInstallationRequestSchema.parse(
        await readJson(request),
    );
    const registered = await registerDeviceInstallation(userId, input);
    // TestFlight and App Store builds share this token, so the other environment's
    // backend would otherwise keep sending its copy of the same notification.
    const projectURL = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "");
    const otherOrigin =
        projectURL === "https://zstzbfocunthczzubggz.supabase.co"
            ? "https://fitfight.app"
            : projectURL === "https://pvqntpteehdvhqyctwum.supabase.co"
              ? "https://staging.fitfight.app"
              : null;
    if (otherOrigin) {
        after(async () => {
            const response = await fetch(
                `${otherOrigin}/api/v1/device-installations/release`,
                {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ token: input.token }),
                },
            );
            if (!response.ok) {
                throw new Error(
                    `Releasing the device on ${otherOrigin} failed with HTTP ${response.status}`,
                );
            }
        });
    }
    return json(registered);
});

export const DELETE = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = revokeDeviceInstallationRequestSchema.parse(
        await readJson(request),
    );
    await revokeDeviceInstallationForToken(userId, input);
    return json({ revoked: true });
});

export const OPTIONS = corsPreflight;
