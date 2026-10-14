import { sendApnsAlert } from "@/lib/apns/apns-client";
import { readApnsEnvironment } from "@/lib/apns/apns-config";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    decryptInstallationToken,
    readActiveDeviceInstallations,
    revokeDeviceInstallation,
} from "@/lib/supabase/queries/device-installations-supabase-query";
import type { ApnsSendInput } from "@/lib/types/notifications/apns";

/**
 * Best effort, like the other alerts: the first installation that accepts the push is enough. The copy follows the
 * language of the newest installation. Does nothing without APNs credentials.
 */
export async function sendUserAlert(
    userId: string,
    alert: (french: boolean) => { title: string; body: string },
    push: Pick<ApnsSendInput, "route" | "collapseId" | "imageUrl">,
) {
    const apns = readApnsEnvironment();
    if (!apns) return;
    const database = createDatabaseClient();
    const installations = await readActiveDeviceInstallations(userId, database);
    const text = alert(installations[0]?.locale === "fr");
    for (const installation of installations) {
        let deviceToken: string;
        try {
            deviceToken = decryptInstallationToken(installation);
        } catch {
            await revokeDeviceInstallation(installation.id, "decrypt_failed", database);
            continue;
        }
        const sent = await sendApnsAlert({
            deviceToken,
            environment: installation.apns_environment,
            topic: apns.topic,
            ...text,
            ...push,
        });
        if (sent.unregistered) {
            await revokeDeviceInstallation(installation.id, sent.reason ?? "unregistered", database);
            continue;
        }
        if (sent.httpStatus === 200 || sent.retryLater || sent.invalidProviderToken) break;
    }
}
