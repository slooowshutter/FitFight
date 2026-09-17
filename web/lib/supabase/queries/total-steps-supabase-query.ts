import { unstable_cache } from "next/cache";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    marketingTotalStepsSchema,
    type MarketingTotalSteps,
} from "@/lib/types/marketing/total-steps";

export const readCachedTotalSteps = unstable_cache(
    async (): Promise<MarketingTotalSteps> => {
        const database = createDatabaseClient();
        const [row] = await database<{ total_steps: string }[]>`
            select coalesce(sum(steps), 0)::text as total_steps
            from public.step_days
        `;
        return marketingTotalStepsSchema.parse({
            totalSteps: row?.total_steps,
        });
    },
    ["marketing-total-steps"],
    { revalidate: 3600 },
);
