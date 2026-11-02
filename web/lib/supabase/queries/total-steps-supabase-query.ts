import { unstable_cache } from "next/cache";
import { stepHistory } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    marketingTotalStepsSchema,
    type MarketingTotalSteps,
} from "@/lib/types/marketing/total-steps";

export const readCachedTotalSteps = unstable_cache(
    async (): Promise<MarketingTotalSteps> => {
        const database = createDatabaseClient();
        const today = new Intl.DateTimeFormat("en-CA", {
            timeZone: "Europe/Paris",
        }).format(new Date());
        // NOTE: since the activity pipeline, step_days only mirrors days inside a Fight, so read
        // the same days as the admin All-time steps card.
        const [row] = await database<{ total_steps: string }[]>`
            select coalesce(sum(history.steps), 0)::bigint::text as total_steps
            from (${stepHistory(database, today, database`'-infinity'::date`)}) as history
            where history.day >= history.joined_day
        `;
        return marketingTotalStepsSchema.parse({
            totalSteps: row?.total_steps,
        });
    },
    ["marketing-total-steps"],
    { revalidate: 3600 },
);
