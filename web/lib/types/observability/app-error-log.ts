import { z } from "zod";

// The PostHog HTTP Webhook destination sends `{ "event": "{event}" }` for each `$exception`.
export const posthogExceptionWebhookSchema = z.object({
    event: z.object({
        uuid: z.string().uuid(),
        event: z.literal("$exception"),
        distinct_id: z.string().min(1).max(200),
        timestamp: z.string().min(1).max(64),
        properties: z.record(z.unknown()),
    }),
});

export type PosthogExceptionWebhook = z.infer<
    typeof posthogExceptionWebhookSchema
>;
