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
    return json(await registerDeviceInstallation(userId, input));
});

export const DELETE = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = revokeDeviceInstallationRequestSchema.parse(
        await readJson(request),
    );
    await revokeDeviceInstallationForToken(userId, input);
    return json({ revoked: true });
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}
