import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    readNotificationPreferences,
    updateNotificationPreferences,
} from "@/lib/supabase/queries/notification-preferences-supabase-query";
import { updateNotificationPreferencesRequestSchema } from "@/lib/types/notifications/notification-preferences";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readNotificationPreferences(userId));
});

export const PATCH = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const parsed = updateNotificationPreferencesRequestSchema.safeParse(
        await readJson(request),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    return json(await updateNotificationPreferences(userId, parsed.data));
});

export const OPTIONS = corsPreflight;
