import { unstable_cache } from "next/cache";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    marketingJoiningLiftSchema,
    type MarketingJoiningLift,
} from "@/lib/types/marketing/joining-lift";
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

/**
 * Same figure as the admin dashboard's "Change after joining" card: the median person's change,
 * in percent, in average daily steps from the 4 weeks before signup to the 4 weeks after.
 * Complete Apple Health days only, people with 7 or more days on each side. Null without data.
 */
export const readCachedJoiningLift = unstable_cache(
    async (): Promise<MarketingJoiningLift> => {
        const database = createDatabaseClient();
        const [row] = await database<{ joining_lift: number | null }[]>`
            with profiles as (
                select user_id, (created_at at time zone 'Europe/Paris')::date as joined_day
                from public.profiles
                where deleted_at is null
            ),
            latest as (
                select distinct on (days.user_id, days.day)
                    days.user_id, days.day, days.steps, days.finalized, days.joined_day
                from (
                    select metric.user_id, metric.day, metric.value::float8 as steps,
                        metric.updated_at, metric.observed_through >= metric.ends_at as finalized,
                        1 as priority, p.joined_day
                    from private.activity_metrics as metric
                    join public.data_sources as source on source.id = metric.source_id
                    join profiles as p on p.user_id = metric.user_id
                    where metric.scope = 'day' and metric.metric = 'steps'
                        and source.provider = 'apple_health'
                        and metric.day >= p.joined_day - 28 and metric.day < p.joined_day + 28
                    union all
                    select legacy.user_id, legacy.day, legacy.value::float8, legacy.updated_at,
                        legacy.finalized_at is not null, 0, p.joined_day
                    from public.metric_days as legacy
                    join public.data_sources as source on source.id = legacy.source_id
                    join profiles as p on p.user_id = legacy.user_id
                    where legacy.metric = 'steps' and source.provider = 'apple_health'
                        and legacy.day >= p.joined_day - 28 and legacy.day < p.joined_day + 28
                ) as days
                order by days.user_id, days.day, days.updated_at desc, days.priority desc
            ),
            compared as (
                select user_id,
                    avg(steps) filter (where day < joined_day) as before,
                    avg(steps) filter (where day >= joined_day) as after
                from latest
                where finalized and day < (now() at time zone 'Europe/Paris')::date
                group by user_id
                having count(*) filter (where day < joined_day) >= 7
                    and count(*) filter (where day >= joined_day) >= 7
            )
            select (percentile_cont(0.5) within group (
                order by 100.0 * (after / before - 1)
            ))::float8 as joining_lift
            from compared
            where before > 0
        `;
        return marketingJoiningLiftSchema.parse({
            joiningLift: row?.joining_lift,
        });
    },
    ["marketing-joining-lift"],
    { revalidate: 3600 },
);
