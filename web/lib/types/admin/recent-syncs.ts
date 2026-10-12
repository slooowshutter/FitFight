import { z } from "zod";

export const recentSyncsSchema = z.object({
    people: z.array(
        z.object({
            user_id: z.string().uuid(),
            handle: z.string(),
            display_name: z.string(),
            last_synced_at: z.string().datetime(),
        }),
    ),
});

export type RecentSyncs = z.infer<typeof recentSyncsSchema>;
