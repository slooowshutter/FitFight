import { after } from "next/server";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { processNotificationOutbox } from "@/lib/supabase/queries/process-notification-outbox-supabase-query";

export function processNotificationOutboxAfterResponse(): void {
    after(async () => {
        await processNotificationOutbox(new Date(), createDatabaseClient());
    });
}
