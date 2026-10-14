import { apiRoute, json, readJson } from "@/lib/http";
import { releaseDeviceInstallationForToken } from "@/lib/supabase/queries/device-installations-supabase-query";
import { revokeDeviceInstallationRequestSchema } from "@/lib/types/notifications/device-installation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Called by the other environment's backend. Knowing the APNs token proves the phone. */
export const POST = apiRoute(async (request) => {
    const input = revokeDeviceInstallationRequestSchema.parse(
        await readJson(request),
    );
    await releaseDeviceInstallationForToken(input);
    return json({ released: true });
});
