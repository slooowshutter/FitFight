import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    adminDashboardCardRowSchema,
    adminDashboardCellRowSchema,
    adminDashboardChartRowSchema,
    adminDashboardSchema,
    adminDashboardSectionValues,
    type AdminDashboard,
    type AdminDashboardCard,
    type AdminDashboardCardDefinition,
    type AdminDashboardChart,
    type AdminDashboardChartDefinition,
    type AdminDashboardEnvironment,
    type AdminDashboardQueryFragment,
    type AdminDashboardSection,
    type AdminDashboardWindow,
} from "@/lib/types/admin/admin-dashboard";

/** Cards compare the last N days with the N days before; rows expose `at` timestamps. */
function eventCard(
    sql: Sql,
    w: AdminDashboardWindow,
    events: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
): AdminDashboardQueryFragment {
    return sql`
        select ${measure} filter (where e.at >= ${w.start} and e.at < ${w.now}) as value,
            ${measure} filter (where e.at >= ${w.previousStart} and e.at < ${w.start}) as previous
        from (${events}) as e
    `;
}

/** Complete civil days only: the last N days before today against the N days before them. */
function dayCard(
    sql: Sql,
    w: AdminDashboardWindow,
    rows: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
): AdminDashboardQueryFragment {
    return sql`
        select ${measure} filter (
                where e.day >= ${w.today}::date - ${w.days}::int and e.day < ${w.today}::date
            ) as value,
            ${measure} filter (
                where e.day >= ${w.today}::date - ${2 * w.days}::int
                    and e.day < ${w.today}::date - ${w.days}::int
            ) as previous
        from (${rows}) as e
    `;
}

/**
 * One point per bucket for the chart window and the equally long window before it.
 * The Nth previous bucket takes the Nth current bucket's date so both series overlay.
 * `complete` rows carry a civil `day` and stop yesterday; other rows carry `at`.
 */
function perBucket(
    sql: Sql,
    w: AdminDashboardWindow,
    rows: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
    complete = false,
): AdminDashboardQueryFragment {
    const lastDay = complete ? sql`(${w.today}::date - 1)` : sql`${w.today}::date`;
    const day = complete ? sql`e.day` : sql`(e.at at time zone 'Europe/Paris')::date`;
    return sql`
        with bounds as (
            select ${lastDay} as last_day,
                ${lastDay} - ${w.chartDays - 1}::int as start_day,
                ${lastDay} - ${2 * w.chartDays - 1}::int as previous_day
        ),
        buckets as (
            select generate_series(
                    date_trunc(${w.bucket}::text, bounds.previous_day::timestamp),
                    date_trunc(${w.bucket}::text, bounds.last_day::timestamp),
                    ('1 ' || ${w.bucket}::text)::interval
                )::date as bucket,
                date_trunc(${w.bucket}::text, bounds.start_day::timestamp)::date as current_bucket
            from bounds
        ),
        measured as (
            select date_trunc(${w.bucket}::text, ${day}::timestamp)::date as bucket, ${measure} as y
            from (${rows}) as e, bounds
            where ${day} between bounds.previous_day and bounds.last_day
            group by 1
        ),
        numbered as (
            select bucket, bucket < current_bucket as previous,
                row_number() over (partition by bucket < current_bucket order by bucket) as position
            from buckets
        )
        select (case when not n.previous then n.bucket
                else coalesce(current.bucket, n.bucket + ${w.chartDays}::int) end)::text as x,
            coalesce(m.y, 0)::float8 as y,
            n.previous
        from numbered as n
        left join numbered as current on n.previous and not current.previous and current.position = n.position
        left join measured as m on m.bucket = n.bucket
        order by n.bucket
    `;
}

/** Sample dates across the chart window, one per bucket, ending today or yesterday. */
function samplePoints(
    sql: Sql,
    w: AdminDashboardWindow,
    complete = false,
): AdminDashboardQueryFragment {
    const lastDay = complete ? sql`(${w.today}::date - 1)` : sql`${w.today}::date`;
    return sql`
        select generate_series(
            (${lastDay} - ${w.chartDays - 1}::int)::timestamp,
            ${lastDay}::timestamp,
            ('1 ' || ${w.bucket}::text)::interval
        )::date as day
    `;
}

function definitions(
    sql: Sql,
    w: AdminDashboardWindow,
    section: AdminDashboardSection,
): { cards: AdminDashboardCardDefinition[]; charts: AdminDashboardChartDefinition[] } {
    const count = sql`count(*)`;
    const people = sql`count(distinct e.user_id)`;
    const profiles = sql`
        select user_id, created_at as at, created_at, handle, handle_set_at, time_zone,
            companion_id, (created_at at time zone 'Europe/Paris')::date as joined_day
        from public.profiles where deleted_at is null
    `;
    // NOTE: a background Health sync ends by refreshing Fights under a "foreground"
    // trace. Traces that follow an observer (background) sync within a minute are not opens.
    const activity = sql`
        select traced.user_id, traced.started_at as at, traced.trigger, traced.app_version, traced.app_build
        from (
            select a.user_id, a.started_at, a.trigger, a.app_version, a.app_build,
                max(a.started_at) filter (where a.trigger = 'observer')
                    over (partition by a.user_id order by a.started_at) as last_observer
            from private.healthkit_sync_attempts as a
            where a.started_at >= ${w.now}::timestamptz - make_interval(days => ${3 * w.chartDays + 60}::int)
        ) as traced
        where traced.trigger in ('foreground', 'manual')
            and (traced.last_observer is null or traced.started_at - traced.last_observer > interval '60 seconds')
    `;
    const opens = sql`select * from (${activity}) as activity where activity.trigger = 'foreground'`;
    const activeDays = sql`
        select distinct user_id, (at at time zone 'Europe/Paris')::date as day from (${activity}) as activity
    `;
    // Same newest-row rule as profile statistics: complete Apple Health days only.
    // Window-bound queries pass a floor so they do not sort years of imported history.
    const stepHistory = (floor: AdminDashboardQueryFragment) => sql`
        select latest.user_id, latest.day, latest.steps, p.joined_day, p.handle
        from (
            select distinct on (days.user_id, days.day) days.user_id, days.day, days.steps, days.finalized
            from (
                select metric.user_id, metric.day, metric.value::float8 as steps, metric.updated_at,
                    metric.observed_through >= metric.ends_at as finalized, 1 as priority
                from private.activity_metrics as metric
                join public.data_sources as source on source.id = metric.source_id
                where metric.scope = 'day' and metric.metric = 'steps' and source.provider = 'apple_health'
                    and metric.day >= ${floor}
                union all
                select legacy.user_id, legacy.day, legacy.value::float8, legacy.updated_at,
                    legacy.finalized_at is not null, 0
                from public.metric_days as legacy
                join public.data_sources as source on source.id = legacy.source_id
                where legacy.metric = 'steps' and source.provider = 'apple_health' and legacy.day >= ${floor}
            ) as days
            order by days.user_id, days.day, days.updated_at desc, days.priority desc
        ) as latest
        join (${profiles}) as p on p.user_id = latest.user_id
        where latest.finalized and latest.day < ${w.today}::date
    `;
    const history = stepHistory(sql`'-infinity'::date`);
    const steps = sql`select * from (${history}) as history where history.day >= history.joined_day`;
    const recentSteps = sql`
        select * from (${stepHistory(sql`${w.today}::date - ${2 * w.chartDays + 7}::int`)}) as history
        where history.day >= history.joined_day
    `;
    const fightDays = sql`
        select s.*, exists (
            select 1 from public.fight_members as m
            join public.fights as f on f.id = m.fight_id
            where m.user_id = s.user_id and m.state = 'accepted' and f.state <> 'cancelled'
                and f.starts_at < (s.day + 1)::timestamp and f.ends_at > s.day::timestamp
        ) as in_fight
        from (${recentSteps}) as s
    `;
    // The app-wide and suggested Fights invite people automatically; they distort social metrics.
    const realFights = sql`
        select f.* from public.fights as f
        left join public.fight_series as series on series.id = f.series_id
        where coalesce(series.join_code, '') <> 'PGG7' and not coalesce(series.suggested, false)
    `;
    const firstRounds = sql`
        select f.id, f.owner_id as user_id, f.created_at as at from (${realFights}) as f
        where not exists (
            select 1 from public.fights as earlier
            where earlier.series_id = f.series_id and earlier.starts_at < f.starts_at
        )
    `;
    const joins = sql`
        select m.user_id, m.accepted_at as at from public.fight_members as m
        join (${realFights}) as f on f.id = m.fight_id
        where m.state = 'accepted' and m.accepted_at is not null and m.user_id <> f.owner_id
    `;
    const totalUsers: AdminDashboardCardDefinition = {
        id: "total_users", title: "Total users", unit: "count", better: true,
        note: "Now vs the start of the period. Deleted accounts are not counted.",
        query: sql`
            select count(*) filter (where created_at < ${w.now})::float8 as value,
                count(*) filter (where created_at < ${w.start})::float8 as previous
            from public.profiles where deleted_at is null
        `,
    };
    const newUsers: AdminDashboardCardDefinition = {
        id: "new_users", title: "New users", unit: "count", better: true,
        query: eventCard(sql, w, profiles, count),
    };
    const newUsersChart: AdminDashboardChartDefinition = {
        id: "new_users_per_bucket", title: "New users", kind: "bar", unit: "count", x: "date",
        note: "Faded bars are the previous period.",
        query: perBucket(sql, w, profiles, count),
    };
    const totalUsersChart: AdminDashboardChartDefinition = {
        id: "total_users_over_time", title: "Total users over time", kind: "line", unit: "count", x: "date",
        query: sql`
            select point.day::text as x, (
                select count(*) from public.profiles as p
                where p.deleted_at is null and (p.created_at at time zone 'Europe/Paris')::date <= point.day
            )::float8 as y
            from (${samplePoints(sql, w)}) as point order by point.day
        `,
    };
    const activeUsers: AdminDashboardCardDefinition = {
        id: "active_users", title: "Active users", unit: "count", better: true,
        note: "Distinct people who opened the app in the period.",
        query: eventCard(sql, w, activity, people),
    };
    const activeUsersChart: AdminDashboardChartDefinition = {
        id: "active_users_per_bucket", title: "Active users", kind: "line", unit: "count", x: "date",
        note: "Distinct people who opened the app per day (or week, month). Dashed: previous period.",
        query: perBucket(sql, w, activity, people),
    };
    const appOpens: AdminDashboardCardDefinition = {
        id: "app_opens", title: "App opens", unit: "count", better: true,
        query: eventCard(sql, w, opens, count),
    };
    const liveFights: AdminDashboardCardDefinition = {
        id: "live_fights", title: "Live fights", unit: "count", better: true,
        note: "Now vs the start of the period, app-wide Fight included.",
        query: sql`
            select count(*) filter (where starts_at <= ${w.now} and ends_at > ${w.now})::float8 as value,
                count(*) filter (where starts_at <= ${w.start} and ends_at > ${w.start})::float8 as previous
            from public.fights where state not in ('draft', 'cancelled')
        `,
    };
    const fightsStarted: AdminDashboardCardDefinition = {
        id: "fights_started", title: "Fights created", unit: "count", better: true,
        note: "New Fights, not later rounds of recurring ones. App-wide and suggested Fights excluded.",
        query: eventCard(sql, w, firstRounds, count),
    };
    const fightsStartedChart: AdminDashboardChartDefinition = {
        id: "fights_created_per_bucket", title: "Fights created", kind: "bar", unit: "count", x: "date",
        query: perBucket(sql, w, firstRounds, count),
    };
    const stepsWalked: AdminDashboardCardDefinition = {
        id: "steps_walked", title: "Steps walked", unit: "steps", better: true,
        note: "Complete days since each person joined, ending yesterday.",
        query: dayCard(sql, w, recentSteps, sql`sum(e.steps)`),
    };
    const allTimeSteps: AdminDashboardCardDefinition = {
        id: "all_time_steps", title: "All-time steps", unit: "steps", better: true,
        note: "Every complete day since each person joined FitFight.",
        query: sql`
            select sum(e.steps)::float8 as value,
                sum(e.steps) filter (where e.day < ${w.today}::date - ${w.days}::int)::float8 as previous
            from (${steps}) as e
        `,
    };
    const averageSteps: AdminDashboardCardDefinition = {
        id: "average_steps", title: "Avg steps per person per day", unit: "steps", better: true,
        query: dayCard(sql, w, recentSteps, sql`avg(e.steps)`),
    };
    const stepsChart: AdminDashboardChartDefinition = {
        id: "steps_per_bucket", title: "Steps walked", kind: "bar", unit: "steps", x: "date",
        query: perBucket(sql, w, recentSteps, sql`sum(e.steps)`, true),
    };

    switch (section) {
        case "overview":
            return {
                cards: [
                    totalUsers, newUsers, activeUsers, appOpens, liveFights, fightsStarted,
                    stepsWalked, allTimeSteps, averageSteps,
                    {
                        id: "health_connected", title: "Apple Health connected", unit: "count", better: true,
                        note: "People with Apple Health connected, now vs the start of the period.",
                        query: sql`
                            select count(distinct user_id) filter (where connected_at < ${w.now})::float8 as value,
                                count(distinct user_id) filter (where connected_at < ${w.start})::float8 as previous
                            from public.data_sources where provider = 'apple_health' and revoked_at is null
                        `,
                    },
                ],
                charts: [
                    totalUsersChart, newUsersChart, activeUsersChart, stepsChart, fightsStartedChart,
                    {
                        id: "overview_opens", title: "App opens", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, opens, count),
                    },
                ],
            };
        case "users":
            return {
                cards: [
                    totalUsers, newUsers,
                    {
                        id: "named_users", title: "Users with a username", unit: "count", better: true,
                        query: sql`
                            select count(*) filter (where handle_set_at < ${w.now})::float8 as value,
                                count(*) filter (where handle_set_at < ${w.start})::float8 as previous
                            from public.profiles where deleted_at is null
                        `,
                    },
                    ...[
                        { id: "onboarding_rate", title: "Picked a username", condition: sql`p.handle_set_at is not null` },
                        { id: "health_rate", title: "Connected Apple Health", condition: sql`exists (
                            select 1 from public.data_sources as s
                            where s.user_id = p.user_id and s.provider = 'apple_health')` },
                        { id: "fight_rate", title: "Joined a fight", condition: sql`exists (
                            select 1 from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                            where m.user_id = p.user_id and m.state = 'accepted')` },
                        { id: "referral_rate", title: "Came from a referral", condition: sql`exists (
                            select 1 from private.referrals as r where r.referred_user_id = p.user_id)` },
                    ].map(({ id, title, condition }): AdminDashboardCardDefinition => ({
                        id, title, unit: "percent", better: true,
                        note: "Share of people who signed up in the period.",
                        query: sql`
                            select 100.0 * count(*) filter (where p.created_at >= ${w.start} and ${condition})
                                    / nullif(count(*) filter (where p.created_at >= ${w.start}), 0) as value,
                                100.0 * count(*) filter (
                                    where p.created_at >= ${w.previousStart} and p.created_at < ${w.start}
                                        and ${condition})
                                    / nullif(count(*) filter (
                                        where p.created_at >= ${w.previousStart} and p.created_at < ${w.start}), 0)
                                    as previous
                            from public.profiles as p
                            where p.deleted_at is null and p.created_at < ${w.now}
                        `,
                    })),
                    {
                        id: "days_to_first_fight", title: "Days to first fight", unit: "days", better: false,
                        note: "Median, for people who signed up in the period and joined a fight.",
                        query: eventCard(sql, w, sql`
                            select * from (
                                select p.user_id, p.created_at as at, extract(epoch from (
                                    select min(m.accepted_at) from public.fight_members as m
                                    join (${realFights}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted'
                                ) - p.created_at) / 86400 as waited
                                from public.profiles as p where p.deleted_at is null
                            ) as waits where waits.waited is not null
                        `, sql`percentile_cont(0.5) within group (order by greatest(e.waited, 0))`),
                    },
                    {
                        id: "referrals", title: "Referrals", unit: "count", better: true,
                        query: eventCard(sql, w, sql`
                            select referrer_user_id as user_id, created_at as at from private.referrals
                        `, count),
                    },
                ],
                charts: [
                    newUsersChart, totalUsersChart,
                    ...[
                        { id: "funnel_period", title: "Onboarding funnel, people who signed up in the period", scope: sql`p.created_at >= ${w.start}` },
                        { id: "funnel_all", title: "Onboarding funnel, everyone", scope: sql`true` },
                    ].map(({ id, title, scope }): AdminDashboardChartDefinition => ({
                        id, title, kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with cohort as (
                                select p.user_id, p.handle_set_at,
                                    exists (select 1 from public.data_sources as s
                                        where s.user_id = p.user_id and s.provider = 'apple_health') as health,
                                    (select count(*) from public.fight_members as m
                                        join (${realFights}) as f on f.id = m.fight_id
                                        where m.user_id = p.user_id and m.state = 'accepted') as fights,
                                    exists (select 1 from public.fight_members as m
                                        join (${realFights}) as f on f.id = m.fight_id
                                        where m.user_id = p.user_id and m.state = 'accepted' and f.state = 'final') as finished
                                from public.profiles as p
                                where p.deleted_at is null and p.created_at < ${w.now} and ${scope}
                            )
                            select x, y::float8 from (values
                                (1, 'Signed up', (select count(*) from cohort)),
                                (2, 'Picked a username', (select count(*) from cohort where handle_set_at is not null)),
                                (3, 'Connected Apple Health', (select count(*) from cohort where health)),
                                (4, 'Joined a fight', (select count(*) from cohort where fights > 0)),
                                (5, 'Finished a fight', (select count(*) from cohort where finished)),
                                (6, 'Joined 2+ fights', (select count(*) from cohort where fights > 1))
                            ) as funnel(position, x, y) order by position
                        `,
                    })),
                    {
                        id: "referrals_per_bucket", title: "Referrals", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, sql`select created_at as at from private.referrals`, count),
                    },
                    {
                        id: "sign_in_methods", title: "Sign-in method", kind: "bar", unit: "count", x: "label",
                        note: "Apple means an Apple sign-in is on file. Older Apple logins without one count as other.",
                        query: sql`
                            select case when exists (
                                    select 1 from private.apple_sign_in_tokens as apple where apple.user_id = p.user_id
                                ) then 'Apple' else 'Google or other' end as x,
                                count(*)::float8 as y
                            from public.profiles as p
                            where p.deleted_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "languages", title: "App language", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select case coalesce(pref.language, 'system')
                                    when 'en' then 'English' when 'fr' then 'French' else 'Follows iPhone' end as x,
                                count(*)::float8 as y
                            from public.profiles as p
                            left join private.account_preferences as pref on pref.user_id = p.user_id
                            where p.deleted_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "regions", title: "Region (from time zone)", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select coalesce(nullif(split_part(time_zone, '/', 1), ''), 'Unknown') as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "time_zones", title: "Top time zones", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select coalesce(time_zone, 'Unknown') as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 2 desc, 1 limit 12
                        `,
                    },
                    {
                        id: "signup_weeks", title: "Signups per week, all time", kind: "bar", unit: "count", x: "date",
                        query: sql`
                            select date_trunc('week', created_at at time zone 'Europe/Paris')::date::text as x,
                                count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 1
                        `,
                    },
                    {
                        id: "signup_weekdays", title: "Signups by weekday, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select to_char(d, 'Dy') as x, (
                                select count(*) from public.profiles as p where p.deleted_at is null
                                    and extract(isodow from p.created_at at time zone 'Europe/Paris') = extract(isodow from d)
                            )::float8 as y
                            from generate_series('2026-09-21'::date, '2026-09-27'::date, interval '1 day') as d order by d
                        `,
                    },
                    {
                        id: "signup_hours", title: "Signups by hour (Paris), all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select lpad(h::text, 2, '0') as x, (
                                select count(*) from public.profiles as p where p.deleted_at is null
                                    and extract(hour from p.created_at at time zone 'Europe/Paris') = h
                            )::float8 as y
                            from generate_series(0, 23) as h order by h
                        `,
                    },
                    {
                        id: "account_age", title: "Account age", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select x, count(p.user_id)::float8 as y from (values
                                (1, 'Under 1 week', interval '0 days', interval '7 days'),
                                (2, '1-4 weeks', interval '7 days', interval '28 days'),
                                (3, '1-3 months', interval '28 days', interval '91 days'),
                                (4, '3-6 months', interval '91 days', interval '182 days'),
                                (5, '6+ months', interval '182 days', interval '100 years')
                            ) as age(position, x, low, high)
                            left join public.profiles as p on p.deleted_at is null
                                and ${w.now} - p.created_at >= age.low and ${w.now} - p.created_at < age.high
                            group by age.position, x order by age.position
                        `,
                    },
                    {
                        id: "top_referrers", title: "Top referrers, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from private.referrals as r join public.profiles as p on p.user_id = r.referrer_user_id
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "companions", title: "Companion choices", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select coalesce(companion_id, 'None yet') as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 2 desc, 1 limit 15
                        `,
                    },
                ],
            };
        case "retention": {
            // NOTE: retention follows people who connected Apple Health. Their phones sync steps
            // in the background, opened or not, until the app is deleted or Health is turned off.
            // App opens can't be used while servers still delete them after 7 days. The floor
            // covers the last 6 signup months and both card periods.
            const synced = sql`
                select distinct history.user_id, history.day
                from (${stepHistory(sql`${w.today}::date - ${Math.max(2 * w.days, 200)}::int`)}) as history
                where history.day >= history.joined_day
            `;
            const withHealth = sql`
                select p.user_id, p.joined_day from (${profiles}) as p
                where exists (
                    select 1 from public.data_sources as s where s.user_id = p.user_id and s.provider = 'apple_health'
                )
            `;
            // Signups in the period vs the period before who synced steps `from` to `to` days
            // after signing up. People count once day `to` has passed.
            const rate = (from: number, to: number) => sql`
                with active as materialized (${synced}),
                eligible as (
                    select c.user_id, c.joined_day, c.joined_day < ${w.today}::date - ${w.days}::int as previous
                    from (${withHealth}) as c
                    where c.joined_day >= ${w.today}::date - ${2 * w.days}::int
                        and c.joined_day + ${to}::int < ${w.today}::date
                ),
                hits as (
                    select distinct e.user_id from eligible as e
                    join active as a on a.user_id = e.user_id
                        and a.day between e.joined_day + ${from}::int and e.joined_day + ${to}::int
                )
                select 100.0 * count(h.user_id) filter (where not e.previous)
                        / nullif(count(*) filter (where not e.previous), 0) as value,
                    100.0 * count(h.user_id) filter (where e.previous)
                        / nullif(count(*) filter (where e.previous), 0) as previous
                from eligible as e
                left join hits as h using (user_id)
            `;
            // One line per signup week (month): the share who synced steps in each week (30-day
            // month) after their own signup day, once it has passed. A signup week (month)
            // appears once its first people reach week (month) 1.
            const curves = (unit: "week" | "month", cohorts: number) => {
                const length = unit === "week" ? 7 : 30;
                return sql`
                    with active as materialized (${synced}),
                    eligible as (
                        select c.user_id, c.cohort, k, c.joined_day + k * ${length}::int as first_day
                        from (
                            select h.user_id, h.joined_day, date_trunc(${unit}::text, h.joined_day::timestamp)::date as cohort
                            from (${withHealth}) as h
                        ) as c
                        cross join generate_series(0, ${cohorts - 1}::int) as k
                        where c.cohort >= date_trunc(${unit}::text, ${w.today}::timestamp) - ${`${cohorts - 1} ${unit}s`}::interval
                            and c.joined_day + (k + 1) * ${length}::int <= ${w.today}::date
                    ),
                    hits as (
                        select distinct e.user_id, e.k from eligible as e
                        join active as a on a.user_id = e.user_id
                            and a.day >= e.first_day and a.day < e.first_day + ${length}::int
                    )
                    select ${unit === "week" ? "W" : "M"}::text || e.k as x,
                        (100.0 * count(h.user_id) / count(*))::float8 as y,
                        to_char(e.cohort::timestamp, ${unit === "week" ? '"Week of "FMDD Mon' : "FMMonth YYYY"}::text) as series
                    from eligible as e
                    left join hits as h on h.user_id = e.user_id and h.k = e.k
                    where e.cohort in (select cohort from eligible where k = 1)
                    group by e.cohort, e.k
                    order by e.cohort desc, e.k
                `;
            };
            return {
                cards: [
                    {
                        id: "signups_with_health", title: "Signups with Apple Health", unit: "count", better: true,
                        note: "The people retention follows: complete days in the period vs the period before.",
                        query: sql`
                            select count(*) filter (where c.joined_day >= ${w.today}::date - ${w.days}::int)::float8 as value,
                                count(*) filter (where c.joined_day < ${w.today}::date - ${w.days}::int)::float8 as previous
                            from (${withHealth}) as c
                            where c.joined_day >= ${w.today}::date - ${2 * w.days}::int and c.joined_day < ${w.today}::date
                        `,
                    },
                    ...[
                        { id: "week_1", title: "Week 1 retention", from: 7, to: 13 },
                        { id: "week_2", title: "Week 2 retention", from: 14, to: 20 },
                        { id: "week_4", title: "Week 4 retention", from: 28, to: 34 },
                        { id: "month_1", title: "Month 1 retention", from: 30, to: 59 },
                        { id: "month_3", title: "Month 3 retention", from: 90, to: 119 },
                    ].map(({ id, title, from, to }): AdminDashboardCardDefinition => ({
                        id, title, unit: "percent", better: true,
                        note: `Synced steps on days ${from} to ${to} after signing up. Signups in the period that got there vs the period before.`,
                        query: rate(from, to),
                    })),
                ],
                charts: [
                    {
                        id: "weekly_cohorts", title: "Weekly retention by signup week", kind: "line", unit: "percent", x: "label",
                        note: "One line per signup week, the last 8. W1 is the share whose phone still synced steps 7 to 13 days after signing up.",
                        query: curves("week", 8),
                    },
                    {
                        id: "monthly_cohorts", title: "Monthly retention by signup month", kind: "line", unit: "percent", x: "label",
                        note: "One line per signup month, the last 6. M1 is days 30 to 59 after signing up.",
                        query: curves("month", 6),
                    },
                ],
            };
        }
        case "engagement":
            return {
                cards: [
                    activeUsers,
                    {
                        id: "daily_active", title: "Avg daily active users", unit: "count", better: true,
                        note: "Average of people who opened the app each day.",
                        query: sql`
                            select (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${w.start} and e.at < ${w.now}))::float8 / ${w.days}::int as value,
                                (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${w.previousStart} and e.at < ${w.start}))::float8 / ${w.days}::int as previous
                            from (${activity}) as e
                        `,
                    },
                    ...[
                        { id: "weekly_active", title: "Weekly active users", span: 7 },
                        { id: "monthly_active", title: "Monthly active users", span: 30 },
                    ].map(({ id, title, span }): AdminDashboardCardDefinition => ({
                        id, title, unit: "count", better: true,
                        note: `People who opened the app in the last ${span} days, now vs the start of the period.`,
                        query: sql`
                            select count(distinct e.user_id) filter (
                                    where e.at >= ${w.now}::timestamptz - make_interval(days => ${span}::int)
                                        and e.at < ${w.now})::float8 as value,
                                count(distinct e.user_id) filter (
                                    where e.at >= ${w.start}::timestamptz - make_interval(days => ${span}::int)
                                        and e.at < ${w.start})::float8 as previous
                            from (${activity}) as e
                        `,
                    })),
                    {
                        id: "stickiness", title: "Stickiness (DAU / MAU)", unit: "percent", better: true,
                        note: "Average daily actives over the last 30 days divided by monthly actives.",
                        query: sql`
                            select 100.0 * (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${w.now}::timestamptz - interval '30 days' and e.at < ${w.now}) / 30.0)
                                    / nullif(count(distinct e.user_id) filter (
                                        where e.at >= ${w.now}::timestamptz - interval '30 days' and e.at < ${w.now}), 0) as value,
                                100.0 * (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${w.start}::timestamptz - interval '30 days' and e.at < ${w.start}) / 30.0)
                                    / nullif(count(distinct e.user_id) filter (
                                        where e.at >= ${w.start}::timestamptz - interval '30 days' and e.at < ${w.start}), 0) as previous
                            from (${activity}) as e
                        `,
                    },
                    appOpens,
                    ...[
                        { id: "opens_p50", title: "Opens per person per day, P50", fraction: 0.5 },
                        { id: "opens_p90", title: "Opens per person per day, P90", fraction: 0.9 },
                        { id: "opens_p99", title: "Opens per person per day, P99", fraction: 0.99 },
                    ].map(({ id, title, fraction }): AdminDashboardCardDefinition => ({
                        id, title, unit: "count", better: true,
                        note: "Among people who opened the app that day.",
                        query: dayCard(sql, w, sql`
                            select user_id, (at at time zone 'Europe/Paris')::date as day, count(*) as opens
                            from (${opens}) as opens group by 1, 2
                        `, sql`percentile_cont(${fraction}::float8) within group (order by e.opens)`),
                    })),
                    {
                        id: "active_days", title: "Active days per active person", unit: "days", better: true,
                        query: sql`
                            with windows as (
                                select case when e.day > ${w.today}::date - ${w.days}::int then 'value' else 'previous' end as period,
                                    e.user_id
                                from (${activeDays}) as e
                                where e.day > ${w.today}::date - ${2 * w.days}::int
                            )
                            select (count(*) filter (where period = 'value'))::float8
                                    / nullif(count(distinct user_id) filter (where period = 'value'), 0) as value,
                                (count(*) filter (where period = 'previous'))::float8
                                    / nullif(count(distinct user_id) filter (where period = 'previous'), 0) as previous
                            from windows
                        `,
                    },
                    {
                        id: "returning", title: "Came back", unit: "percent", better: true,
                        note: "Share of the previous period's active people who were active again.",
                        query: sql`
                            with before as (
                                select distinct user_id from (${activity}) as e
                                where e.at >= ${w.previousStart} and e.at < ${w.start}
                            ), after as (
                                select distinct user_id from (${activity}) as e
                                where e.at >= ${w.start} and e.at < ${w.now}
                            ), earlier as (
                                select distinct user_id from (${activity}) as e
                                where e.at >= ${w.previousStart}::timestamptz - (${w.start}::timestamptz - ${w.previousStart}::timestamptz)
                                    and e.at < ${w.previousStart}
                            )
                            select 100.0 * (select count(*) from before join after using (user_id))
                                    / nullif((select count(*) from before), 0) as value,
                                100.0 * (select count(*) from earlier join before using (user_id))
                                    / nullif((select count(*) from earlier), 0) as previous
                        `,
                    },
                    {
                        id: "lapsed", title: "Lapsed for 14+ days", unit: "count", better: false,
                        note: "Opened the app before, not in the last 14 days. Now vs the start of the period.",
                        query: sql`
                            with last_open as (
                                select user_id, max(at) filter (where at < ${w.now}) as now_last,
                                    max(at) filter (where at < ${w.start}) as start_last
                                from (${activity}) as e group by user_id
                            )
                            select count(*) filter (where now_last < ${w.now}::timestamptz - interval '14 days')::float8 as value,
                                count(*) filter (where start_last < ${w.start}::timestamptz - interval '14 days')::float8 as previous
                            from last_open
                        `,
                    },
                    {
                        id: "churned", title: "Did not come back", unit: "count", better: false,
                        note: "Active in the previous period, not in this one.",
                        query: sql`
                            with before as (
                                select distinct user_id from (${activity}) as e
                                where e.at >= ${w.previousStart} and e.at < ${w.start}
                            ), after as (
                                select distinct user_id from (${activity}) as e
                                where e.at >= ${w.start} and e.at < ${w.now}
                            )
                            select (select count(*) from before where user_id not in (select user_id from after))::float8 as value,
                                null::float8 as previous
                        `,
                    },
                ],
                charts: [
                    activeUsersChart,
                    {
                        id: "dau_wau_mau", title: "Daily, weekly and monthly active users", kind: "line", unit: "count", x: "date",
                        query: sql`
                            with point as (${samplePoints(sql, w)}), counted as (
                                select point.day,
                                    count(distinct a.user_id) filter (where a.day = point.day) as daily,
                                    count(distinct a.user_id) filter (where a.day > point.day - 7) as weekly,
                                    count(distinct a.user_id) filter (where a.day > point.day - 30) as monthly
                                from point left join (${activeDays}) as a
                                    on a.day <= point.day and a.day > point.day - 30
                                group by point.day
                            )
                            select counted.day::text as x, value.y::float8 as y, value.series
                            from counted cross join lateral (values
                                (1, 'DAU', counted.daily), (2, 'WAU', counted.weekly), (3, 'MAU', counted.monthly)
                            ) as value(position, series, y)
                            order by value.position, counted.day
                        `,
                    },
                    {
                        id: "opens_per_bucket", title: "App opens", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, opens, count),
                    },
                    {
                        id: "opens_percentiles", title: "Opens per person per day: P50, P90, P99", kind: "line", unit: "count", x: "date",
                        note: "Among people who opened the app that day.",
                        query: sql`
                            with daily as (
                                select user_id, (at at time zone 'Europe/Paris')::date as day, count(*) as opens
                                from (${opens}) as opens
                                where (at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                                group by 1, 2
                            ), bucketed as (
                                select date_trunc(${w.bucket}::text, day::timestamp)::date as bucket,
                                    percentile_cont(0.5) within group (order by opens) as p50,
                                    percentile_cont(0.9) within group (order by opens) as p90,
                                    percentile_cont(0.99) within group (order by opens) as p99
                                from daily group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values
                                ('P50', bucketed.p50), ('P90', bucketed.p90), ('P99', bucketed.p99)
                            ) as value(series, y)
                            order by value.series, bucketed.bucket
                        `,
                    },
                    {
                        id: "opens_distribution", title: "Opens per person-day", kind: "bar", unit: "count", x: "label",
                        note: "How many times people opened the app on the days they opened it, in the period.",
                        query: sql`
                            with daily as (
                                select user_id, (at at time zone 'Europe/Paris')::date as day, count(*) as opens
                                from (${opens}) as opens
                                where at >= ${w.start} and at < ${w.now} group by 1, 2
                            )
                            select bucket.x, count(daily.opens)::float8 as y from (values
                                (1, '1', 1, 1), (2, '2', 2, 2), (3, '3-4', 3, 4), (4, '5-9', 5, 9),
                                (5, '10-19', 10, 19), (6, '20+', 20, 1000000)
                            ) as bucket(position, x, low, high)
                            left join daily on daily.opens between bucket.low and bucket.high
                            group by bucket.position, bucket.x order by bucket.position
                        `,
                    },
                    {
                        id: "opens_heatmap", title: "When people open the app (Paris time)", kind: "heatmap", unit: "count", x: "label",
                        note: "Opens in the chart period by weekday and hour.",
                        query: sql`
                            with counted as (
                                select extract(isodow from o.at at time zone 'Europe/Paris')::int as d,
                                    extract(hour from o.at at time zone 'Europe/Paris')::int as h, count(*) as n
                                from (${opens}) as o
                                where (o.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                                group by 1, 2
                            )
                            select lpad(h::text, 2, '0') as x, to_char('2026-09-20'::date + d, 'Dy') as y,
                                coalesce(counted.n, 0)::float8 as value
                            from generate_series(1, 7) as d cross join generate_series(0, 23) as h
                            left join counted using (d, h)
                            order by d, h
                        `,
                    },
                    {
                        id: "active_days_histogram", title: "Active days per person in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with per_person as (
                                select user_id, count(*) as days from (${activeDays}) as a
                                where a.day > ${w.today}::date - ${w.days}::int group by 1
                            )
                            select bucket.x, count(per_person.days)::float8 as y from (values
                                (1, '1 day', 1, 1), (2, '2-3', 2, 3), (3, '4-7', 4, 7),
                                (4, '8-14', 8, 14), (5, '15-30', 15, 30), (6, '31+', 31, 100000)
                            ) as bucket(position, x, low, high)
                            left join per_person on per_person.days between bucket.low and bucket.high
                            group by bucket.position, bucket.x order by bucket.position
                        `,
                    },
                    {
                        id: "retention_cohorts", title: "Weekly retention by signup week", kind: "heatmap", unit: "percent", x: "label",
                        note: "Share of each signup week's people who opened the app N weeks later.",
                        query: sql`
                            with cohort as (
                                select user_id, date_trunc('week', created_at at time zone 'Europe/Paris')::date as week
                                from public.profiles
                                where deleted_at is null
                                    and created_at >= date_trunc('week', ${w.now}::timestamptz) - interval '7 weeks'
                            ), sizes as (select week, count(*) as people from cohort group by 1),
                            returned as (
                                select cohort.week, (a.day - cohort.week) / 7 as n, count(distinct a.user_id) as people
                                from cohort join (${activeDays}) as a using (user_id)
                                where a.day >= cohort.week group by 1, 2
                            )
                            select 'W' || n as x, sizes.week::text as y,
                                (100.0 * coalesce(returned.people, 0) / sizes.people)::float8 as value
                            from sizes cross join generate_series(0, 7) as n
                            left join returned using (week, n)
                            where sizes.week + 7 * n <= ${w.today}::date
                            order by sizes.week, n
                        `,
                    },
                    {
                        id: "new_vs_returning", title: "New vs returning active people", kind: "bar", unit: "count", x: "date",
                        note: "New: signed up the same day (or week, month).",
                        query: sql`
                            select date_trunc(${w.bucket}::text, a.day::timestamp)::date::text as x,
                                count(distinct a.user_id)::float8 as y,
                                case when date_trunc(${w.bucket}::text, p.joined_day::timestamp)
                                    = date_trunc(${w.bucket}::text, a.day::timestamp) then 'New' else 'Returning' end as series
                            from (${activeDays}) as a join (${profiles}) as p using (user_id)
                            where a.day > ${w.today}::date - ${w.chartDays}::int
                            group by 1, 3 order by 3, 1
                        `,
                    },
                    {
                        id: "opens_by_version", title: "Opens by app version", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select app_version || ' (' || app_build || ')' as x, count(*)::float8 as y
                            from (${opens}) as o where o.at >= ${w.start} and o.at < ${w.now}
                            group by 1 order by 2 desc limit 12
                        `,
                    },
                    {
                        id: "recency", title: "Days since people last opened the app", kind: "bar", unit: "count", x: "label",
                        note: "Everyone with an account; Never means no open recorded since sync history started.",
                        query: sql`
                            with last_open as (
                                select p.user_id, ${w.today}::date - max(a.day) as days
                                from public.profiles as p left join (${activeDays}) as a using (user_id)
                                where p.deleted_at is null group by p.user_id
                            )
                            select band.x, (case when band.position = 7 then (select count(*) from last_open where days is null)
                                else (select count(*) from last_open where days >= band.low and days < band.high) end)::float8 as y
                            from (values
                                (1, 'Today', 0, 1), (2, '1-2 days', 1, 3), (3, '3-7 days', 3, 8), (4, '8-14 days', 8, 15),
                                (5, '15-30 days', 15, 31), (6, '31+ days', 31, 1000000), (7, 'Never', 0, 0)
                            ) as band(position, x, low, high) order by band.position
                        `,
                    },
                    {
                        id: "opens_by_weekday", title: "Opens by weekday", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with counted as (
                                select extract(isodow from o.at at time zone 'Europe/Paris')::int as d, count(*) as n
                                from (${opens}) as o
                                where (o.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                                group by 1
                            )
                            select to_char('2026-09-20'::date + d, 'Dy') as x, coalesce(counted.n, 0)::float8 as y
                            from generate_series(1, 7) as d left join counted using (d) order by d
                        `,
                    },
                    {
                        id: "opens_by_hour", title: "Opens by hour (Paris time)", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with counted as (
                                select extract(hour from o.at at time zone 'Europe/Paris')::int as h, count(*) as n
                                from (${opens}) as o
                                where (o.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                                group by 1
                            )
                            select lpad(h::text, 2, '0') as x, coalesce(counted.n, 0)::float8 as y
                            from generate_series(0, 23) as h left join counted using (h) order by h
                        `,
                    },
                    {
                        id: "opens_per_active_person", title: "Opens per active person", kind: "line", unit: "count", x: "date",
                        note: "App opens divided by people who opened the app, per day (or week, month). Dashed: previous period.",
                        query: perBucket(sql, w, activity, sql`
                            count(*) filter (where e.trigger = 'foreground')::float8 / nullif(count(distinct e.user_id), 0)
                        `),
                    },
                    {
                        id: "top_openers", title: "Most active people in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from (${opens}) as o join public.profiles as p on p.user_id = o.user_id
                            where o.at >= ${w.start} and o.at < ${w.now}
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                ],
            };
        case "steps":
            return {
                cards: [
                    allTimeSteps, stepsWalked, averageSteps,
                    {
                        id: "median_steps", title: "Median steps per person per day", unit: "steps", better: true,
                        query: dayCard(sql, w, recentSteps, sql`percentile_cont(0.5) within group (order by e.steps)`),
                    },
                    {
                        id: "walkers", title: "People with step data", unit: "count", better: true,
                        query: dayCard(sql, w, recentSteps, people),
                    },
                    {
                        id: "ten_k_days", title: "Days over 10K steps", unit: "percent", better: true,
                        query: dayCard(sql, w, recentSteps, sql`avg(case when e.steps >= 10000 then 100.0 else 0 end)`),
                    },
                    {
                        id: "best_day", title: "Best single day", unit: "steps", better: true,
                        query: dayCard(sql, w, recentSteps, sql`max(e.steps)`),
                    },
                    {
                        id: "fight_day_lift", title: "Fight-day lift", unit: "percent", better: true,
                        note: "How much more people walk on days they are in a live Fight than on other days.",
                        query: sql`
                            with windows as (
                                select case when e.day >= ${w.today}::date - ${w.days}::int then 'value' else 'previous' end as period,
                                    e.steps, e.in_fight
                                from (${fightDays}) as e
                                where e.day >= ${w.today}::date - ${2 * w.days}::int
                            )
                            select 100.0 * (avg(steps) filter (where period = 'value' and in_fight)
                                    / nullif(avg(steps) filter (where period = 'value' and not in_fight), 0) - 1) as value,
                                100.0 * (avg(steps) filter (where period = 'previous' and in_fight)
                                    / nullif(avg(steps) filter (where period = 'previous' and not in_fight), 0) - 1) as previous
                            from windows
                        `,
                    },
                    {
                        id: "joining_lift", title: "Change after joining", unit: "percent", better: true,
                        note: "Median change: each person's 4 weeks after signup vs the 4 weeks before (7+ days of data each side).",
                        query: sql`
                            with compared as (
                                select user_id,
                                    avg(steps) filter (where day >= joined_day - 28 and day < joined_day) as before,
                                    avg(steps) filter (where day >= joined_day and day < joined_day + 28) as after
                                from (${history}) as h group by user_id
                                having count(*) filter (where day >= joined_day - 28 and day < joined_day) >= 7
                                    and count(*) filter (where day >= joined_day and day < joined_day + 28) >= 7
                            )
                            select percentile_cont(0.5) within group (order by 100.0 * (after / nullif(before, 0) - 1)) as value,
                                null::float8 as previous
                            from compared where before > 0
                        `,
                    },
                    {
                        id: "history_steps", title: "Steps in Health history", unit: "steps", better: true,
                        note: "All imported Apple Health days, including before people joined.",
                        query: sql`
                            select sum(e.steps)::float8 as value,
                                sum(e.steps) filter (where e.day < ${w.today}::date - ${w.days}::int)::float8 as previous
                            from (${history}) as e
                        `,
                    },
                    {
                        id: "history_days", title: "Person-days of Health history", unit: "count", better: true,
                        query: sql`
                            select count(*)::float8 as value,
                                count(*) filter (where e.day < ${w.today}::date - ${w.days}::int)::float8 as previous
                            from (${history}) as e
                        `,
                    },
                ],
                charts: [
                    stepsChart,
                    {
                        id: "average_steps_per_bucket", title: "Avg steps per person per day", kind: "line", unit: "steps", x: "date",
                        note: "Dashed: previous period.",
                        query: perBucket(sql, w, recentSteps, sql`avg(e.steps)`, true),
                    },
                    {
                        id: "rolling_average", title: "7-day rolling avg steps per person", kind: "line", unit: "steps", x: "date",
                        query: sql`
                            with daily as materialized (
                                select s.day, sum(s.steps) as total, count(*) as people from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - ${w.chartDays + 7}::int group by 1
                            )
                            select point.day::text as x, coalesce((
                                select sum(daily.total) / nullif(sum(daily.people), 0) from daily
                                where daily.day > point.day - 7 and daily.day <= point.day
                            ), 0)::float8 as y
                            from (${samplePoints(sql, w, true)}) as point order by point.day
                        `,
                    },
                    {
                        id: "mean_median", title: "Mean vs median steps per person per day", kind: "line", unit: "steps", x: "date",
                        note: "A gap means a few big walkers pull the mean up.",
                        query: sql`
                            with bucketed as (
                                select date_trunc(${w.bucket}::text, day::timestamp)::date as bucket,
                                    avg(steps) as mean, percentile_cont(0.5) within group (order by steps) as median
                                from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - ${w.chartDays}::int
                                group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values ('Mean', bucketed.mean), ('Median', bucketed.median))
                                as value(series, y)
                            order by value.series, bucketed.bucket
                        `,
                    },
                    {
                        id: "level_mix", title: "Days by companion level", kind: "bar", unit: "percent", x: "label",
                        note: "Share of person-days in the period at each level.",
                        query: sql`
                            with days as (
                                select steps from (${recentSteps}) as s where s.day >= ${w.today}::date - ${w.days}::int
                            )
                            select level.x, (100.0 * count(days.steps) / nullif((select count(*) from days), 0))::float8 as y
                            from (values
                                (1, 'Under 3K', 0, 3000), (2, '3K-6K', 3000, 6000), (3, '6K-10K', 6000, 10000),
                                (4, '10K-15K', 10000, 15000), (5, '15K+', 15000, 100000000)
                            ) as level(position, x, low, high)
                            left join days on days.steps >= level.low and days.steps < level.high
                            group by level.position, level.x order by level.position
                        `,
                    },
                    {
                        id: "people_by_average", title: "People by their daily average", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with people as (
                                select user_id, avg(steps) as steps from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - ${w.days}::int group by 1
                            )
                            select level.x, count(people.user_id)::float8 as y from (values
                                (1, 'Under 3K', 0, 3000), (2, '3K-6K', 3000, 6000), (3, '6K-10K', 6000, 10000),
                                (4, '10K-15K', 10000, 15000), (5, '15K+', 15000, 100000000)
                            ) as level(position, x, low, high)
                            left join people on people.steps >= level.low and people.steps < level.high
                            group by level.position, level.x order by level.position
                        `,
                    },
                    {
                        id: "weekday_steps", title: "Avg steps by weekday", kind: "bar", unit: "steps", x: "label",
                        query: sql`
                            with days as (
                                select extract(isodow from s.day)::int as d, avg(s.steps) as steps from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - ${w.chartDays}::int group by 1
                            )
                            select to_char('2026-09-20'::date + d, 'Dy') as x, coalesce(days.steps, 0)::float8 as y
                            from generate_series(1, 7) as d left join days using (d) order by d
                        `,
                    },
                    {
                        id: "around_joining", title: "Steps around joining (day 0 = signup)", kind: "line", unit: "steps", x: "label",
                        note: "Average across everyone with Health history on those days.",
                        query: sql`
                            select (day - joined_day)::text as x, avg(steps)::float8 as y
                            from (${history}) as h
                            where day - joined_day between -28 and 28
                            group by day - joined_day order by day - joined_day
                        `,
                    },
                    {
                        id: "before_after", title: "4 weeks before vs after joining", kind: "bar", unit: "steps", x: "label",
                        note: "Same people on both sides, 7+ days of data each.",
                        query: sql`
                            with compared as (
                                select user_id,
                                    avg(steps) filter (where day >= joined_day - 28 and day < joined_day) as before,
                                    avg(steps) filter (where day >= joined_day and day < joined_day + 28) as after
                                from (${history}) as h group by user_id
                                having count(*) filter (where day >= joined_day - 28 and day < joined_day) >= 7
                                    and count(*) filter (where day >= joined_day and day < joined_day + 28) >= 7
                            )
                            select x, y::float8 from (values
                                (1, 'Before', (select avg(before) from compared)),
                                (2, 'After', (select avg(after) from compared))
                            ) as side(position, x, y) where y is not null order by position
                        `,
                    },
                    {
                        id: "fight_vs_other_days", title: "Fight days vs other days", kind: "bar", unit: "steps", x: "label",
                        note: "Average steps in the period on days in a live Fight vs days without one.",
                        query: sql`
                            with days as (
                                select * from (${fightDays}) as d where d.day >= ${w.today}::date - ${w.chartDays}::int
                            )
                            select x, y::float8 from (values
                                (1, 'In a fight', (select avg(steps) from days where in_fight)),
                                (2, 'Other days', (select avg(steps) from days where not in_fight))
                            ) as side(position, x, y) where y is not null order by position
                        `,
                    },
                    {
                        id: "final_day_push", title: "Last day of a fight vs its other days", kind: "bar", unit: "steps", x: "label",
                        note: "Accepted fighters in finished Fights, all time.",
                        query: sql`
                            with fight_days as (
                                select s.steps, s.day = (f.ends_at - interval '1 second')::date as last_day
                                from public.fights as f
                                join public.fight_members as m on m.fight_id = f.id and m.state = 'accepted'
                                join (${steps}) as s on s.user_id = m.user_id
                                    and s.day between f.starts_at::date and (f.ends_at - interval '1 second')::date
                                where f.state = 'final' and f.ends_at - f.starts_at > interval '1 day'
                            )
                            select x, y::float8 from (values
                                (1, 'Last day', (select avg(steps) from fight_days where last_day)),
                                (2, 'Other days', (select avg(steps) from fight_days where not last_day))
                            ) as side(position, x, y) where y is not null order by position
                        `,
                    },
                    {
                        id: "joining_change_distribution", title: "Change after joining, per person", kind: "bar", unit: "count", x: "label",
                        note: "Each person's 4 weeks after signup vs the 4 weeks before (7+ days of data each side).",
                        query: sql`
                            with compared as (
                                select 100.0 * (avg(steps) filter (where day >= joined_day and day < joined_day + 28)
                                    / nullif(avg(steps) filter (where day >= joined_day - 28 and day < joined_day), 0) - 1) as change
                                from (${history}) as h group by user_id
                                having count(*) filter (where day >= joined_day - 28 and day < joined_day) >= 7
                                    and count(*) filter (where day >= joined_day and day < joined_day + 28) >= 7
                            )
                            select band.x, count(compared.change)::float8 as y from (values
                                (1, 'Down 20%+', -1000000, -20), (2, 'Down 5-20%', -20, -5), (3, 'About the same', -5, 5),
                                (4, 'Up 5-20%', 5, 20), (5, 'Up 20%+', 20, 1000000)
                            ) as band(position, x, low, high)
                            left join compared on compared.change >= band.low and compared.change < band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "ten_k_share_per_bucket", title: "Share of days over 10K", kind: "line", unit: "percent", x: "date",
                        note: "Dashed: previous period.",
                        query: perBucket(sql, w, recentSteps, sql`avg(case when e.steps >= 10000 then 100.0 else 0 end)`, true),
                    },
                    {
                        id: "steps_by_region", title: "Avg steps by region", kind: "bar", unit: "steps", x: "label",
                        note: "Region from each person's time zone, complete days in the period.",
                        query: sql`
                            select coalesce(nullif(split_part(p.time_zone, '/', 1), ''), 'Unknown') as x, avg(s.steps)::float8 as y
                            from (${recentSteps}) as s join public.profiles as p on p.user_id = s.user_id
                            where s.day >= ${w.today}::date - ${w.days}::int
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "top_walkers", title: "Top walkers in the period", kind: "bar", unit: "steps", x: "label",
                        query: sql`
                            select '@' || handle as x, sum(steps)::float8 as y from (${recentSteps}) as s
                            where s.day >= ${w.today}::date - ${w.days}::int
                            group by handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "best_days", title: "Best single days in the period", kind: "bar", unit: "steps", x: "label",
                        query: sql`
                            select '@' || handle || ', ' || to_char(day, 'DD Mon') as x, steps::float8 as y
                            from (${recentSteps}) as s where s.day >= ${w.today}::date - ${w.days}::int
                            order by steps desc, handle limit 10
                        `,
                    },
                    {
                        id: "cumulative_steps", title: "All-time steps over time", kind: "line", unit: "steps", x: "date",
                        query: sql`
                            with running as materialized (
                                select day, sum(sum(s.steps)) over (order by s.day) as total
                                from (${steps}) as s group by s.day
                            )
                            select point.day::text as x, coalesce((
                                select running.total from running where running.day <= point.day
                                order by running.day desc limit 1
                            ), 0)::float8 as y
                            from (${samplePoints(sql, w, true)}) as point order by point.day
                        `,
                    },
                    {
                        id: "monthly_steps", title: "Steps per month since joining, all time", kind: "bar", unit: "steps", x: "date",
                        query: sql`
                            select date_trunc('month', day::timestamp)::date::text as x, sum(steps)::float8 as y
                            from (${steps}) as s group by 1 order by 1
                        `,
                    },
                    {
                        id: "history_depth", title: "How far back Health history goes", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with depth as (
                                select user_id, ${w.today}::date - min(day) as days from (${history}) as h group by 1
                            )
                            select span.x, count(depth.user_id)::float8 as y from (values
                                (1, 'Under 1 year', 0, 365), (2, '1-2 years', 365, 730), (3, '2-5 years', 730, 1826),
                                (4, '5-10 years', 1826, 3652), (5, '10+ years', 3652, 1000000)
                            ) as span(position, x, low, high)
                            left join depth on depth.days >= span.low and depth.days < span.high
                            group by span.position, span.x order by span.position
                        `,
                    },
                ],
            };
        case "fights":
            return {
                cards: [
                    liveFights, fightsStarted,
                    {
                        id: "rounds_finished", title: "Rounds finished", unit: "count", better: true,
                        query: eventCard(sql, w, sql`select ends_at as at from public.fights where state = 'final'`, count),
                    },
                    {
                        id: "joins", title: "People joining fights", unit: "count", better: true,
                        note: "Accepted memberships, not counting the creator. App-wide and suggested Fights excluded.",
                        query: eventCard(sql, w, joins, count),
                    },
                    {
                        id: "fighters_per_fight", title: "Fighters per fight", unit: "count", better: true,
                        note: "Average accepted fighters in Fights that started in the period.",
                        query: eventCard(sql, w, sql`
                            select f.starts_at as at, (select count(*) from public.fight_members as m
                                where m.fight_id = f.id and m.state = 'accepted') as fighters
                            from (${realFights}) as f where f.state <> 'cancelled'
                        `, sql`avg(e.fighters)`),
                    },
                    {
                        id: "people_in_fights", title: "People in a live fight", unit: "percent", better: true,
                        note: "Share of all users, now vs the start of the period.",
                        query: sql`
                            select 100.0 * (select count(distinct m.user_id) from public.fight_members as m
                                    join public.fights as f on f.id = m.fight_id
                                    where m.state = 'accepted' and f.state not in ('draft', 'cancelled')
                                        and f.starts_at <= ${w.now} and f.ends_at > ${w.now})
                                    / nullif((select count(*) from public.profiles
                                        where deleted_at is null and created_at < ${w.now}), 0) as value,
                                100.0 * (select count(distinct m.user_id) from public.fight_members as m
                                    join public.fights as f on f.id = m.fight_id
                                    where m.state = 'accepted' and f.state not in ('draft', 'cancelled')
                                        and f.starts_at <= ${w.start} and f.ends_at > ${w.start})
                                    / nullif((select count(*) from public.profiles
                                        where deleted_at is null and created_at < ${w.start}), 0) as previous
                        `,
                    },
                    {
                        id: "invite_acceptance", title: "Invites accepted", unit: "percent", better: true,
                        note: "Share of people invited in the period who are now in the Fight.",
                        query: eventCard(sql, w, sql`
                            select event.occurred_at as at, bool_or(m.state = 'accepted') as accepted
                            from private.fight_membership_events as event
                            join (${realFights}) as f on f.id = event.fight_id
                            left join public.fight_members as m on m.fight_id = event.fight_id and m.user_id = event.user_id
                            where event.state = 'invited' and event.occurred_at is not null
                            group by event.fight_id, event.user_id, event.occurred_at
                        `, sql`avg(case when e.accepted then 100.0 else 0 end)`),
                    },
                    {
                        id: "cancel_rate", title: "Cancelled", unit: "percent", better: false,
                        note: "Share of Fights starting in the period that were cancelled.",
                        query: eventCard(sql, w, sql`select starts_at as at, state from (${realFights}) as f`,
                            sql`avg(case when e.state = 'cancelled' then 100.0 else 0 end)`),
                    },
                    {
                        id: "recurring_share", title: "Recurring fights", unit: "percent", better: null,
                        note: "Share of new Fights created as recurring.",
                        query: eventCard(sql, w, sql`
                            select series.created_at as at, series.recurring from public.fight_series as series
                            where series.join_code <> 'PGG7' and not series.suggested
                        `, sql`avg(case when e.recurring then 100.0 else 0 end)`),
                    },
                    {
                        id: "winning_margin", title: "Median winning margin", unit: "percent", better: null,
                        note: "Winner's lead over second place, Fights finished in the period.",
                        query: eventCard(sql, w, sql`
                            select f.ends_at as at, 100.0 * (ranked.first - ranked.second) / nullif(ranked.first, 0) as margin
                            from public.fights as f
                            cross join lateral (
                                select max(m.final_value) filter (where m.rank = 1) as first,
                                    max(m.final_value) filter (where m.rank = 2) as second
                                from public.fight_members as m where m.fight_id = f.id and m.state = 'accepted'
                            ) as ranked
                            where f.state = 'final' and ranked.second is not null
                        `, sql`percentile_cont(0.5) within group (order by e.margin)`),
                    },
                ],
                charts: [
                    fightsStartedChart,
                    {
                        id: "live_fights_over_time", title: "Live fights over time", kind: "line", unit: "count", x: "date",
                        query: sql`
                            select point.day::text as x, (
                                select count(*) from public.fights as f
                                where f.state not in ('draft', 'cancelled')
                                    and f.starts_at < (point.day + 1)::timestamp and f.ends_at > (point.day + 1)::timestamp
                            )::float8 as y
                            from (${samplePoints(sql, w)}) as point order by point.day
                        `,
                    },
                    {
                        id: "rounds_finished_per_bucket", title: "Rounds finished", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, sql`select ends_at as at from public.fights where state = 'final'`, count),
                    },
                    {
                        id: "joins_per_bucket", title: "People joining fights", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, joins, count),
                    },
                    {
                        id: "invites_per_bucket", title: "Invites sent", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, sql`
                            select event.occurred_at as at from private.fight_membership_events as event
                            join (${realFights}) as f on f.id = event.fight_id
                            where event.state = 'invited' and event.occurred_at is not null
                        `, count),
                    },
                    {
                        id: "fighter_steps", title: "Avg daily steps of people in a live fight", kind: "line", unit: "steps", x: "date",
                        note: "Dashed: previous period.",
                        query: perBucket(sql, w, sql`select * from (${fightDays}) as d where d.in_fight`, sql`avg(e.steps)`, true),
                    },
                    {
                        id: "fight_sizes", title: "Fight sizes", kind: "bar", unit: "count", x: "label",
                        note: "Fights that started in the chart period, by accepted fighters.",
                        query: sql`
                            with sizes as (
                                select (select count(*) from public.fight_members as m
                                    where m.fight_id = f.id and m.state = 'accepted') as fighters
                                from (${realFights}) as f
                                where f.state <> 'cancelled' and (f.starts_at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                            )
                            select size.x, count(sizes.fighters)::float8 as y from (values
                                (1, 'Solo', 0, 1), (2, '1v1', 2, 2), (3, '3-5', 3, 5), (4, '6-10', 6, 10), (5, '11+', 11, 1000000)
                            ) as size(position, x, low, high)
                            left join sizes on sizes.fighters between size.low and size.high
                            group by size.position, size.x order by size.position
                        `,
                    },
                    {
                        id: "durations", title: "Fight durations, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select duration.x, count(series.id)::float8 as y from (values
                                (1, 'Up to 1 day', 0, 86400), (2, '2-3 days', 86401, 259200), (3, '4-7 days', 259201, 604800),
                                (4, '8-14 days', 604801, 1209600), (5, '15-31 days', 1209601, 2678400), (6, 'Longer', 2678401, 2147483647)
                            ) as duration(position, x, low, high)
                            left join public.fight_series as series on series.duration_seconds between duration.low and duration.high
                                and series.join_code <> 'PGG7' and not series.suggested
                            group by duration.position, duration.x order by duration.position
                        `,
                    },
                    {
                        id: "fight_states", title: "Fights by state, created in the chart period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select initcap(replace(state::text, '_', ' ')) as x, count(*)::float8 as y
                            from (${realFights}) as f where (f.created_at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                            group by state order by 2 desc
                        `,
                    },
                    {
                        id: "margins", title: "How close fights end", kind: "bar", unit: "count", x: "label",
                        note: "Winner's lead over second place, finished Fights, all time.",
                        query: sql`
                            with margins as (
                                select 100.0 * (ranked.first - ranked.second) / nullif(ranked.first, 0) as margin
                                from public.fights as f
                                cross join lateral (
                                    select max(m.final_value) filter (where m.rank = 1) as first,
                                        max(m.final_value) filter (where m.rank = 2) as second
                                    from public.fight_members as m where m.fight_id = f.id and m.state = 'accepted'
                                ) as ranked
                                where f.state = 'final' and ranked.second is not null
                            )
                            select band.x, count(margins.margin)::float8 as y from (values
                                (1, 'Under 5%', 0, 5), (2, '5-15%', 5, 15), (3, '15-30%', 15, 30),
                                (4, '30-50%', 30, 50), (5, '50%+', 50, 100.0001)
                            ) as band(position, x, low, high)
                            left join margins on margins.margin >= band.low and margins.margin < band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "time_to_first_fight", title: "Time from signup to first fight", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with waits as (
                                select extract(epoch from (
                                    select min(m.accepted_at) from public.fight_members as m
                                    join (${realFights}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted'
                                ) - p.created_at) / 86400 as days
                                from public.profiles as p where p.deleted_at is null
                            )
                            select band.x, (case when band.position = 6 then (select count(*) from waits where days is null)
                                else (select count(*) from waits where greatest(days, 0) >= band.low and days < band.high) end)::float8 as y
                            from (values
                                (1, 'Same day', 0, 1), (2, '1-3 days', 1, 4), (3, '4-7 days', 4, 8),
                                (4, '8-30 days', 8, 31), (5, '31+ days', 31, 1000000), (6, 'Not yet', 0, 0)
                            ) as band(position, x, low, high) order by band.position
                        `,
                    },
                    {
                        id: "top_fighters", title: "Most fights joined, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                            join public.profiles as p on p.user_id = m.user_id
                            where m.state = 'accepted' group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_winners", title: "Most wins, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                            join public.profiles as p on p.user_id = m.user_id
                            where m.state = 'accepted' and m.rank = 1 and f.state = 'final'
                                and (select count(*) from public.fight_members as other
                                    where other.fight_id = f.id and other.state = 'accepted') > 1
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "loser_actions", title: "Most common loser actions", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select left(lower(trim(action_text)), 40) as x, count(*)::float8 as y
                            from public.fight_series where action_text is not null and trim(action_text) <> ''
                                and join_code <> 'PGG7' and not suggested
                            group by 1 order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "rounds_per_series", title: "Rounds per recurring fight", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with rounds as (
                                select series.id, count(f.id) as rounds from public.fight_series as series
                                join public.fights as f on f.series_id = series.id
                                where series.recurring and series.join_code <> 'PGG7' group by series.id
                            )
                            select band.x, count(rounds.id)::float8 as y from (values
                                (1, '1 round', 1, 1), (2, '2', 2, 2), (3, '3-5', 3, 5), (4, '6-10', 6, 10), (5, '11+', 11, 1000000)
                            ) as band(position, x, low, high)
                            left join rounds on rounds.rounds between band.low and band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "fight_start_weekdays", title: "Fights created by weekday, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select to_char('2026-09-20'::date + d, 'Dy') as x, (
                                select count(*) from (${firstRounds}) as f
                                where extract(isodow from f.at at time zone 'Europe/Paris') = d
                            )::float8 as y
                            from generate_series(1, 7) as d order by d
                        `,
                    },
                    {
                        id: "visibility", title: "Public vs private fights, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select case visibility when 'joinable' then 'Public' else 'Private' end as x, count(*)::float8 as y
                            from public.fight_series where join_code <> 'PGG7' and not suggested group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "app_wide_members", title: "App-wide and suggested fights", kind: "bar", unit: "count", x: "label",
                        note: "Accepted fighters in each, all rounds.",
                        query: sql`
                            select left(series.name, 40) as x, count(distinct m.user_id)::float8 as y
                            from public.fight_series as series
                            join public.fights as f on f.series_id = series.id
                            join public.fight_members as m on m.fight_id = f.id and m.state = 'accepted'
                            where series.join_code = 'PGG7' or series.suggested
                            group by series.id, series.name order by 2 desc limit 10
                        `,
                    },
                ],
            };
        case "social": {
            const posts = sql`select author_id as user_id, created_at as at from public.fight_posts`;
            const comments = sql`select author_id as user_id, created_at as at from public.fight_post_comments`;
            const reactions = sql`select user_id, created_at as at, emoji from public.fight_post_reactions`;
            const friendships = sql`
                select requester_id as user_id, accepted_at as at from private.profile_friendships
                where state = 'accepted' and accepted_at is not null
            `;
            return {
                cards: [
                    { id: "posts", title: "Posts", unit: "count", better: true, query: eventCard(sql, w, posts, count) },
                    { id: "comments", title: "Comments", unit: "count", better: true, query: eventCard(sql, w, comments, count) },
                    { id: "reactions", title: "Reactions", unit: "count", better: true, query: eventCard(sql, w, reactions, count) },
                    {
                        id: "posters", title: "People posting", unit: "count", better: true,
                        note: "Wrote a post or a comment.",
                        query: eventCard(sql, w, sql`${posts} union all ${comments}`, people),
                    },
                    {
                        id: "feedback_items", title: "Bugs and requests", unit: "count", better: null,
                        query: eventCard(sql, w, sql`select author_id as user_id, created_at as at from public.feedback_posts`, count),
                    },
                    {
                        id: "feedback_votes", title: "Feedback votes", unit: "count", better: true,
                        query: eventCard(sql, w, sql`select user_id, created_at as at from public.feedback_votes`, count),
                    },
                    {
                        id: "friendships", title: "New friendships", unit: "count", better: true,
                        query: eventCard(sql, w, friendships, count),
                    },
                    {
                        id: "reports", title: "Post reports", unit: "count", better: false,
                        query: eventCard(sql, w, sql`select reporter_id as user_id, created_at as at from private.fight_post_reports`, count),
                    },
                ],
                charts: [
                    { id: "posts_per_bucket", title: "Posts", kind: "bar", unit: "count", x: "date", query: perBucket(sql, w, posts, count) },
                    { id: "comments_per_bucket", title: "Comments", kind: "bar", unit: "count", x: "date", query: perBucket(sql, w, comments, count) },
                    { id: "reactions_per_bucket", title: "Reactions", kind: "bar", unit: "count", x: "date", query: perBucket(sql, w, reactions, count) },
                    {
                        id: "friendships_per_bucket", title: "New friendships", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, friendships, count),
                    },
                    {
                        id: "feedback_per_bucket", title: "Bugs vs feature requests", kind: "bar", unit: "count", x: "date",
                        query: sql`
                            select date_trunc(${w.bucket}::text, (created_at at time zone 'Europe/Paris')::date::timestamp)::date::text as x,
                                count(*)::float8 as y, case kind when 'bug' then 'Bugs' else 'Features' end as series
                            from public.feedback_posts
                            where (created_at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                            group by 1, 3 order by 3, 1
                        `,
                    },
                    {
                        id: "top_emojis", title: "Top reactions in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select emoji as x, count(*)::float8 as y from (${reactions}) as r
                            where r.at >= ${w.start} and r.at < ${w.now} group by emoji order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_posters", title: "Most posts and comments in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from (${posts} union all ${comments}) as e join public.profiles as p on p.user_id = e.user_id
                            where e.at >= ${w.start} and e.at < ${w.now}
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_feedback", title: "Most voted open bugs and requests", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select left(post.title, 40) as x, count(vote.user_id)::float8 as y
                            from public.feedback_posts as post
                            left join public.feedback_votes as vote on vote.post_id = post.id
                            where not post.archived group by post.id, post.title order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "posts_by_fight", title: "Fights with the most posts, all time", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select left(f.name, 40) as x, count(*)::float8 as y
                            from public.fight_posts as post join public.fights as f on f.id = post.fight_id
                            group by f.id, f.name order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "media_uploads", title: "Media uploaded in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select initcap(kind::text) || ' for ' || replace(purpose::text, '_', ' ') as x, count(*)::float8 as y
                            from public.media_objects
                            where created_at >= ${w.start} and created_at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "social_heatmap", title: "When people post, comment and react (Paris time)", kind: "heatmap", unit: "count", x: "label",
                        query: sql`
                            with events as (${posts} union all ${comments} union all select user_id, at from (${reactions}) as r),
                            counted as (
                                select extract(isodow from e.at at time zone 'Europe/Paris')::int as d,
                                    extract(hour from e.at at time zone 'Europe/Paris')::int as h, count(*) as n
                                from events as e
                                where (e.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                                group by 1, 2
                            )
                            select lpad(h::text, 2, '0') as x, to_char('2026-09-20'::date + d, 'Dy') as y,
                                coalesce(counted.n, 0)::float8 as value
                            from generate_series(1, 7) as d cross join generate_series(0, 23) as h
                            left join counted using (d, h)
                            order by d, h
                        `,
                    },
                ],
            };
        }
        case "app": {
            const attempts = sql`
                select user_id, started_at as at, trigger, outcome, error_code, total_ms, app_version, app_build
                from private.healthkit_sync_attempts
            `;
            const errors = sql`select user_id, created_at as at, path, status from private.server_error_logs`;
            return {
                cards: [
                    {
                        id: "health_share", title: "Apple Health connected", unit: "percent", better: true,
                        note: "Share of users, now vs the start of the period.",
                        query: sql`
                            select 100.0 * (select count(distinct user_id) from public.data_sources
                                    where provider = 'apple_health' and revoked_at is null and connected_at < ${w.now})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${w.now}), 0) as value,
                                100.0 * (select count(distinct user_id) from public.data_sources
                                    where provider = 'apple_health' and revoked_at is null and connected_at < ${w.start})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${w.start}), 0) as previous
                        `,
                    },
                    {
                        id: "sync_success", title: "Syncs that succeeded", unit: "percent", better: true,
                        query: eventCard(sql, w, attempts, sql`avg(case when e.outcome = 'succeeded' then 100.0 else 0 end)`),
                    },
                    {
                        id: "background_syncs", title: "Background syncs", unit: "count", better: true,
                        note: "Apple Health woke the app to sync without anyone opening it.",
                        query: eventCard(sql, w, sql`select * from (${attempts}) as a where a.trigger = 'observer'`, count),
                    },
                    {
                        id: "sync_time", title: "Median sync time", unit: "seconds", better: false,
                        query: eventCard(sql, w, attempts, sql`percentile_cont(0.5) within group (order by e.total_ms / 1000.0)`),
                    },
                    {
                        id: "push_share", title: "Push notifications on", unit: "percent", better: true,
                        note: "Share of users with an authorized device, now.",
                        query: sql`
                            select 100.0 * (select count(distinct user_id) from private.device_installations
                                    where revoked_at is null and permission_status in ('authorized', 'provisional', 'ephemeral'))
                                    / nullif((select count(*) from public.profiles where deleted_at is null), 0) as value,
                                null::float8 as previous
                        `,
                    },
                    {
                        id: "notifications_sent", title: "Notifications sent", unit: "count", better: null,
                        query: eventCard(sql, w, sql`
                            select user_id, coalesce(processed_at, created_at) as at from private.notification_intents where status = 'sent'
                        `, count),
                    },
                    {
                        id: "server_errors", title: "Server errors", unit: "count", better: false,
                        query: eventCard(sql, w, errors, count),
                    },
                    {
                        id: "latest_build_share", title: "Active people on the newest build", unit: "percent", better: true,
                        note: "Newest build seen in the period.",
                        query: sql`
                            with latest as (
                                select distinct on (user_id) user_id, app_build
                                from (${attempts}) as a where a.at >= ${w.start} and a.at < ${w.now}
                                order by user_id, a.at desc
                            ), newest as (
                                select max(app_build::bigint) as build from latest where app_build ~ '^[0-9]+$'
                            )
                            select 100.0 * count(*) filter (where latest.app_build = newest.build::text)
                                    / nullif(count(*), 0) as value,
                                null::float8 as previous
                            from latest cross join newest
                        `,
                    },
                    {
                        id: "sync_issue_users", title: "People with a sync error now", unit: "count", better: false,
                        query: sql`
                            select count(*)::float8 as value, null::float8 as previous
                            from private.healthkit_sync_diagnostics where error_code is not null
                        `,
                    },
                ],
                charts: [
                    {
                        id: "builds_in_use", title: "Builds in use", kind: "bar", unit: "count", x: "label",
                        note: "People by the newest build they used in the period.",
                        query: sql`
                            select version as x, count(*)::float8 as y from (
                                select distinct on (user_id) user_id, app_version || ' (' || app_build || ')' as version
                                from (${attempts}) as a where a.at >= ${w.start} and a.at < ${w.now}
                                order by user_id, a.at desc
                            ) as latest group by 1 order by 2 desc, 1 limit 12
                        `,
                    },
                    {
                        id: "sync_triggers", title: "Why syncs happened", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select case trigger when 'foreground' then 'App opened' when 'observer' then 'Background'
                                    else 'Pull to refresh' end as x, count(*)::float8 as y
                            from (${attempts}) as a where a.at >= ${w.start} and a.at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "sync_outcomes", title: "Sync outcomes", kind: "bar", unit: "count", x: "date",
                        query: sql`
                            select date_trunc(${w.bucket}::text, (at at time zone 'Europe/Paris')::date::timestamp)::date::text as x,
                                count(*)::float8 as y, initcap(outcome) as series
                            from (${attempts}) as a
                            where (a.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int
                            group by 1, 3 order by 3, 1
                        `,
                    },
                    {
                        id: "sync_durations", title: "Sync time: P50 and P90", kind: "line", unit: "seconds", x: "date",
                        query: sql`
                            with bucketed as (
                                select date_trunc(${w.bucket}::text, (at at time zone 'Europe/Paris')::date::timestamp)::date as bucket,
                                    percentile_cont(0.5) within group (order by total_ms / 1000.0) as p50,
                                    percentile_cont(0.9) within group (order by total_ms / 1000.0) as p90
                                from (${attempts}) as a
                                where (a.at at time zone 'Europe/Paris')::date > ${w.today}::date - ${w.chartDays}::int group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values ('P50', bucketed.p50), ('P90', bucketed.p90)) as value(series, y)
                            order by value.series, bucketed.bucket
                        `,
                    },
                    {
                        id: "syncs_per_person_day", title: "Syncs per person-day", kind: "bar", unit: "count", x: "label",
                        note: "All triggers, in the period.",
                        query: sql`
                            with daily as (
                                select user_id, (at at time zone 'Europe/Paris')::date, count(*) as syncs
                                from (${attempts}) as a where a.at >= ${w.start} and a.at < ${w.now} group by 1, 2
                            )
                            select band.x, count(daily.syncs)::float8 as y from (values
                                (1, '1', 1, 1), (2, '2-3', 2, 3), (3, '4-6', 4, 6), (4, '7-12', 7, 12), (5, '13-24', 13, 24), (6, '25+', 25, 1000000)
                            ) as band(position, x, low, high)
                            left join daily on daily.syncs between band.low and band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "sync_error_codes", title: "Sync errors in the period", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select replace(error_code, '_', ' ') as x, count(*)::float8 as y
                            from (${attempts}) as a
                            where a.error_code is not null and a.at >= ${w.start} and a.at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "errors_per_bucket", title: "Server errors", kind: "bar", unit: "count", x: "date",
                        query: perBucket(sql, w, errors, count),
                    },
                    {
                        id: "errors_by_path", title: "Server errors by route", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select left(path, 48) as x, count(*)::float8 as y from (${errors}) as e
                            where e.at >= ${w.start} and e.at < ${w.now} group by 1 order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "errors_by_status", title: "Server errors by status", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select status::text as x, count(*)::float8 as y from (${errors}) as e
                            where e.at >= ${w.start} and e.at < ${w.now} group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "notifications_by_kind", title: "Notifications sent by kind", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select replace(kind, '_', ' ') as x, count(*)::float8 as y from private.notification_intents
                            where status = 'sent' and coalesce(processed_at, created_at) >= ${w.start}
                                and coalesce(processed_at, created_at) < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "notification_outcomes", title: "Notification outcomes", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select initcap(status) || coalesce(': ' || replace(skip_reason, '_', ' '), '') as x, count(*)::float8 as y
                            from private.notification_intents
                            where created_at >= ${w.start} and created_at < ${w.now}
                            group by 1 order by 2 desc limit 12
                        `,
                    },
                    {
                        id: "push_permissions", title: "Push permission on devices", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select initcap(replace(coalesce(permission_status, 'unknown'), '_', ' ')) as x, count(*)::float8 as y
                            from private.device_installations where revoked_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "background_refresh", title: "Background App Refresh", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select initcap(coalesce(background_refresh_status, 'unknown')) as x, count(*)::float8 as y
                            from private.healthkit_sync_diagnostics group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "last_sync_age", title: "Time since last Apple Health sync", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            with ages as (
                                select extract(epoch from (${w.now} - max(last_success_at))) / 3600 as hours
                                from public.data_sources where provider = 'apple_health' and revoked_at is null
                                group by user_id
                            )
                            select band.x, (case when band.position = 7 then (select count(*) from ages where hours is null)
                                else (select count(*) from ages where hours >= band.low and hours < band.high) end)::float8 as y
                            from (values
                                (1, 'Under 1 hour', 0, 1), (2, '1-6 hours', 1, 6), (3, '6-24 hours', 6, 24),
                                (4, '1-3 days', 24, 72), (5, '3-7 days', 72, 168), (6, 'Over a week', 168, 10000000),
                                (7, 'Never', 0, 0)
                            ) as band(position, x, low, high) order by band.position
                        `,
                    },
                    {
                        id: "apns_results", title: "Apple push delivery results", kind: "bar", unit: "count", x: "label",
                        query: sql`
                            select coalesce(apns_http_status::text, 'No response') || coalesce(' ' || apns_reason, '') as x,
                                count(*)::float8 as y
                            from private.notification_deliveries
                            where coalesce(sent_at, created_at) >= ${w.start} and coalesce(sent_at, created_at) < ${w.now}
                            group by 1 order by 2 desc limit 10
                        `,
                    },
                ],
            };
        }
    }
}

/**
 * Operator-only aggregates, computed live from Postgres on every request.
 * Each card or chart is one query, so a failing query only marks its own tile.
 */
export async function readAdminDashboard(
    section: AdminDashboardSection,
    days: number,
    environment: AdminDashboardEnvironment,
    database: Sql = createDatabaseClient(),
): Promise<AdminDashboard> {
    const now = new Date();
    const chartDays = Math.max(days, 7);
    const w: AdminDashboardWindow = {
        now,
        start: new Date(now.getTime() - days * 86_400_000),
        previousStart: new Date(now.getTime() - 2 * days * 86_400_000),
        today: new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris" }).format(now),
        days,
        chartDays,
        bucket: chartDays <= 62 ? "day" : chartDays <= 366 ? "week" : "month",
    };
    const { cards, charts } = definitions(database, w, section);
    const failure = (error: unknown) => `Query failed: ${error instanceof Error ? error.message : String(error)}`;
    return adminDashboardSchema.parse({
        section,
        days,
        environment,
        generated_at: now.toISOString(),
        sections: adminDashboardSectionValues.map((id) => ({ id, title: id[0].toUpperCase() + id.slice(1) })),
        cards: await Promise.all(cards.map(async (card): Promise<AdminDashboardCard> => {
            const tile = { id: card.id, title: card.title, unit: card.unit, higher_is_better: card.better };
            try {
                const row = adminDashboardCardRowSchema.parse((await card.query)[0]);
                return { ...tile, ...row, note: card.note ?? null };
            } catch (error) {
                return { ...tile, value: null, previous: null, note: failure(error) };
            }
        })),
        charts: await Promise.all(charts.map(async (chart): Promise<AdminDashboardChart> => {
            const tile = { id: chart.id, title: chart.title, kind: chart.kind, unit: chart.unit, x_kind: chart.x };
            try {
                const rows = await chart.query;
                if (chart.kind === "heatmap") {
                    return { ...tile, note: chart.note ?? null, series: [], cells: rows.map((row) => adminDashboardCellRowSchema.parse(row)) };
                }
                const series = new Map<string, AdminDashboardChart["series"][number]>();
                for (const raw of rows) {
                    const row = adminDashboardChartRowSchema.parse(raw);
                    const previous = row.previous ?? false;
                    const name = row.series ?? (previous ? "Previous period" : "This period");
                    const line = series.get(`${name}:${previous}`) ?? { name, previous, points: [] };
                    line.points.push({ x: row.x, y: row.y });
                    series.set(`${name}:${previous}`, line);
                }
                return { ...tile, note: chart.note ?? null, series: [...series.values()], cells: [] };
            } catch (error) {
                return { ...tile, note: failure(error), series: [], cells: [] };
            }
        })),
    });
}
