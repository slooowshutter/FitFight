import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { PosthogExceptionWebhook } from "@/lib/types/observability/app-error-log";

/** Saves one PostHog `$exception`. A retried delivery of the same event is ignored. */
export async function insertAppErrorLog(
    { event }: PosthogExceptionWebhook,
    database: Sql = createDatabaseClient(),
): Promise<boolean> {
    const properties = event.properties;
    const text = (value: unknown) =>
        typeof value === "string" && value !== "" ? value : null;
    const first = Array.isArray(properties.$exception_list)
        ? (properties.$exception_list[0] as Record<string, unknown> | undefined)
        : undefined;
    const issue = text(properties.$exception_issue_id);
    const rows = await database`
        insert into private.app_error_logs (
            posthog_event_id, occurred_at, environment, distinct_id,
            app_version, app_build, error_type, message, posthog_issue_id, properties
        ) values (
            ${event.uuid}, ${event.timestamp}::timestamptz, ${text(properties.environment)}, ${event.distinct_id},
            ${text(properties.$app_version)}, ${text(properties.$app_build)},
            ${text(first?.type) ?? text(properties.$exception_type)},
            ${text(first?.value) ?? text(properties.$exception_message)},
            ${issue && /^[0-9a-f-]{36}$/i.test(issue) ? issue : null},
            ${JSON.stringify(properties)}::jsonb
        )
        on conflict (posthog_event_id) do nothing
        returning id
    `;
    return rows.length > 0;
}
