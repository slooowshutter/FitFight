import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    adminDashboardCardRowSchema,
    adminDashboardCellRowSchema,
    adminDashboardChartRowSchema,
    adminDashboardRangeRowSchema,
    adminDashboardSchema,
    adminDashboardSectionValues,
    type AdminDashboard,
    type AdminDashboardBucket,
    type AdminDashboardCard,
    type AdminDashboardCardDefinition,
    type AdminDashboardChart,
    type AdminDashboardChartDefinition,
    type AdminDashboardEnvironment,
    type AdminDashboardExampleReader,
    type AdminDashboardQueryFragment,
    type AdminDashboardSection,
    type AdminDashboardWindow,
} from "@/lib/types/admin/admin-dashboard";

/** The last `span` days, rolling to now, against the `span` days before them; rows expose `at`. */
function eventCard(
    sql: Sql,
    w: AdminDashboardWindow,
    span: number,
    events: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
): AdminDashboardQueryFragment {
    const start = new Date(w.now.getTime() - span * 86_400_000);
    const previousStart = new Date(w.now.getTime() - 2 * span * 86_400_000);
    return sql`
        select ${measure} filter (where e.at >= ${start} and e.at < ${w.now}) as value,
            ${measure} filter (where e.at >= ${previousStart} and e.at < ${start}) as previous
        from (${events}) as e
    `;
}

/** Complete Paris days: the `span` days before today against the `span` days before them. */
function dayCard(
    sql: Sql,
    w: AdminDashboardWindow,
    span: number,
    rows: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
): AdminDashboardQueryFragment {
    return sql`
        select ${measure} filter (
                where e.day >= ${w.today}::date - ${span}::int and e.day < ${w.today}::date
            ) as value,
            ${measure} filter (
                where e.day >= ${w.today}::date - ${2 * span}::int and e.day < ${w.today}::date - ${span}::int
            ) as previous
        from (${rows}) as e
    `;
}

/**
 * One point per bucket from the chart start through today (yesterday for `complete` rows, which
 * carry a civil `day`; other rows carry `at`). Counts fill empty buckets with 0; `gaps` leaves them
 * out, for averages and shares. `series` lists the values of the rows' `series` column in legend
 * order, so a series keeps its place and colour whatever the period.
 */
function perBucket(
    sql: Sql,
    w: AdminDashboardWindow,
    rows: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
    { complete = false, gaps = false, series }: { complete?: boolean; gaps?: boolean; series?: string[] } = {},
): AdminDashboardQueryFragment {
    const lastDay = complete ? sql`(${w.today}::date - 1)` : sql`${w.today}::date`;
    const day = complete ? sql`e.day` : sql`(e.at at time zone 'Europe/Paris')::date`;
    return sql`
        with buckets as (
            select generate_series(${w.start}::timestamp, date_trunc(${w.bucket}::text, ${lastDay}::timestamp),
                ('1 ' || ${w.bucket}::text)::interval)::date as bucket
        ),
        listed as (
            ${series
                ? sql`select * from unnest(${sql.array(series)}::text[]) with ordinality as listed(series, position)`
                : sql`select null::text as series, 1::bigint as position`}
        ),
        measured as (
            select date_trunc(${w.bucket}::text, ${day}::timestamp)::date as bucket,
                ${series ? sql`e.series` : sql`null::text`} as series, ${measure} as y
            from (${rows}) as e
            where ${day} between ${w.start}::date and ${lastDay}
            group by 1, 2
        )
        select b.bucket::text as x, ${gaps ? sql`m.y` : sql`coalesce(m.y, 0)`}::float8 as y, l.series
        from buckets as b
        cross join listed as l
        left join measured as m on m.bucket = b.bucket and m.series is not distinct from l.series
        ${gaps ? sql`where m.y is not null` : sql``}
        order by l.position, b.bucket
    `;
}

/** Each chart bucket with the day a running total or state is read on: its last day so far. */
function samplePoints(sql: Sql, w: AdminDashboardWindow): AdminDashboardQueryFragment {
    return sql`
        select bucket::date as bucket,
            least((bucket + ('1 ' || ${w.bucket}::text)::interval)::date - 1, ${w.today}::date) as day
        from generate_series(${w.start}::timestamp, date_trunc(${w.bucket}::text, ${w.today}::timestamp),
            ('1 ' || ${w.bucket}::text)::interval) as bucket
    `;
}

/** Reads a built chart for its example sentence, in English like the rest of the dashboard. */
function exampleReader(chart: AdminDashboardChart, w: AdminDashboardWindow): AdminDashboardExampleReader {
    const points = (name?: string) => (name ? chart.series.find((line) => line.name === name) : chart.series[0])?.points ?? [];
    // NOTE: fixed names, because English short months differ by ICU version ("Sep" or "Sept").
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const date = (x: string) => new Date(`${x}T00:00:00Z`);
    const dayMonth = (x: string) => `${date(x).getUTCDate()} ${months[date(x).getUTCMonth()]}`;
    const end = (x: string) => {
        const next = new Date(`${x}T00:00:00Z`);
        if (w.bucket === "month") next.setUTCMonth(next.getUTCMonth() + 1);
        else next.setUTCDate(next.getUTCDate() + (w.bucket === "week" ? 7 : 1));
        return next.toISOString().slice(0, 10);
    };
    const xs = chart.x_kind === "date" ? [...new Set(chart.series.flatMap((line) => line.points.map((point) => point.x)))].sort() : [];
    const reference = xs.filter((x) => end(x) <= w.today).at(-1) ?? xs.at(-1);
    const filling = reference !== undefined && end(reference) > w.today;
    const day = (x: string) => `${["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date(x).getUTCDay()]} ${dayMonth(x)}`;
    const period = (x: string) => w.bucket === "day" ? day(x) : w.bucket === "week" ? `the week of ${dayMonth(x)}`
        : new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric", timeZone: "UTC" }).format(date(x));
    const format = (value: number, unit = chart.unit) => {
        const digits = value.toLocaleString("en-US", { maximumFractionDigits: unit === "steps" ? 0 : 1 });
        if (unit === "percent") return `${digits}%`;
        if (unit === "count" || unit === "steps") return digits;
        return `${digits} ${value === 1 ? unit.slice(0, -1) : unit}`;
    };
    const share = (part: number, whole: number) => (whole > 0 ? format((100 * part) / whole, "percent") : undefined);
    const rows = points();
    const total = rows.reduce((sum, row) => sum + row.y, 0);
    const top = rows.reduce<{ x: string; y: number } | undefined>((best, row) => (!best || row.y > best.y ? row : best), undefined);
    const peak = chart.cells.reduce<AdminDashboardChart["cells"][number] | undefined>(
        (best, cell) => (!best || cell.value > best.value ? cell : best), undefined);
    return {
        when: reference === undefined ? ""
            : filling ? `${w.bucket === "day" ? "today" : `this ${w.bucket}`} so far`
            : `${w.bucket === "day" ? "on" : "in"} ${period(reference)}`,
        at: (series) => points(series).find((point) => point.x === reference)?.y,
        latest: (series) => points(series).at(-1)?.y,
        first: (series) => points(series)[0],
        series: chart.series,
        rows,
        row: (label) => rows.find((row) => row.x === label)?.y,
        total,
        top: top && { ...top, share: share(top.y, total) },
        peak,
        format,
        count: (value, one, many) => `${format(value, "count")} ${value === 1 ? one : many}`,
        share,
        day,
        period,
    };
}

/**
 * Cards have fixed spans named in their titles, so the app's period never changes them. Charts
 * over time (`x` date) cover the chosen period. Other charts name their own fixed span.
 */
function definitions(
    sql: Sql,
    w: AdminDashboardWindow,
    section: AdminDashboardSection,
): { cards: AdminDashboardCardDefinition[]; charts: AdminDashboardChartDefinition[] } {
    const count = sql`count(*)`;
    const people = sql`count(distinct e.user_id)`;
    const per = `per ${w.bucket}`;
    const ago = (days: number) => new Date(w.now.getTime() - days * 86_400_000);
    const profiles = sql`
        select user_id, created_at as at, created_at, handle, handle_set_at, time_zone,
            companion_id, (created_at at time zone 'Europe/Paris')::date as joined_day
        from public.profiles where deleted_at is null
    `;
    // NOTE: a background Health sync ends by refreshing Fights under a "foreground"
    // trace. Traces that follow an observer (background) sync within a minute are not opens.
    const activitySince = (floor: AdminDashboardQueryFragment) => sql`
        select traced.user_id, traced.started_at as at, traced.trigger, traced.app_version, traced.app_build
        from (
            select a.user_id, a.started_at, a.trigger, a.app_version, a.app_build,
                max(a.started_at) filter (where a.trigger = 'observer')
                    over (partition by a.user_id order by a.started_at) as last_observer
            from private.healthkit_sync_attempts as a
            where a.started_at >= ${floor}
        ) as traced
        where traced.trigger in ('foreground', 'manual')
            and (traced.last_observer is null or traced.started_at - traced.last_observer > interval '60 seconds')
    `;
    // The month before the chart start feeds its monthly actives; 61 days feed the monthly cards.
    const activity = activitySince(
        sql`least(${w.start}::date - 31, ${w.today}::date - 61)::timestamp at time zone 'Europe/Paris'`,
    );
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
        select * from (${stepHistory(sql`least(${w.start}::date, ${w.today}::date - 61)`)}) as history
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
        note: "Now, vs 7 days ago. Deleted accounts are not counted.",
        query: sql`
            select count(*)::float8 as value, count(*) filter (where created_at < ${ago(7)})::float8 as previous
            from public.profiles where deleted_at is null
        `,
    };
    const weeklyNewUsers: AdminDashboardCardDefinition = {
        id: "new_users", title: "Weekly new users", unit: "count", better: true,
        note: "Last 7 days vs the 7 before.",
        query: eventCard(sql, w, 7, profiles, count),
    };
    const weeklyActive: AdminDashboardCardDefinition = {
        id: "weekly_active", title: "Weekly active users", unit: "count", better: true,
        note: "Opened the app in the last 7 days, vs the 7 before.",
        query: eventCard(sql, w, 7, activity, people),
    };
    const monthlyActive: AdminDashboardCardDefinition = {
        id: "monthly_active", title: "Monthly active users", unit: "count", better: true,
        note: "Opened the app in the last 30 days, vs the 30 before.",
        query: eventCard(sql, w, 30, activity, people),
    };
    const weeklyOpens: AdminDashboardCardDefinition = {
        id: "app_opens", title: "Weekly app opens", unit: "count", better: true,
        note: "Last 7 days vs the 7 before.",
        query: eventCard(sql, w, 7, opens, count),
    };
    const liveFights: AdminDashboardCardDefinition = {
        id: "live_fights", title: "Live fights", unit: "count", better: true,
        note: "Now, vs 7 days ago. App-wide Fight included.",
        query: sql`
            select count(*) filter (where starts_at <= ${w.now} and ends_at > ${w.now})::float8 as value,
                count(*) filter (where starts_at <= ${ago(7)} and ends_at > ${ago(7)})::float8 as previous
            from public.fights where state not in ('draft', 'cancelled')
        `,
    };
    const weeklyFightsCreated: AdminDashboardCardDefinition = {
        id: "fights_started", title: "Weekly fights created", unit: "count", better: true,
        note: "New Fights, not later rounds or app-wide ones. Last 7 days vs the 7 before.",
        query: eventCard(sql, w, 7, firstRounds, count),
    };
    const weeklySteps: AdminDashboardCardDefinition = {
        id: "steps_walked", title: "Weekly steps", unit: "steps", better: true,
        note: "The 7 complete days before today, vs the 7 before.",
        query: dayCard(sql, w, 7, recentSteps, sql`sum(e.steps)`),
    };
    const totalUsersChart: AdminDashboardChartDefinition = {
        id: "total_users_over_time", title: "Total users", kind: "line", unit: "count", x: "date",
        definition: `Everyone with a FitFight account at the end of each ${w.bucket}, and now for the last point. Deleted accounts are not counted.`,
        example: (r) => {
            const now = r.latest();
            const start = r.first();
            return now === undefined || !start ? null
                : `FitFight has ${r.count(now, "user", "users")} now, against ${r.format(start.y)} at the end of ${r.period(start.x)}.`;
        },
        note: `At the end of each ${w.bucket}, now for the last one.`,
        query: sql`
            select point.bucket::text as x, (
                select count(*) from public.profiles as p
                where p.deleted_at is null and (p.created_at at time zone 'Europe/Paris')::date <= point.day
            )::float8 as y
            from (${samplePoints(sql, w)}) as point order by point.bucket
        `,
    };
    const newUsersChart: AdminDashboardChartDefinition = {
        id: "new_users_per_bucket", title: `New users ${per}`, kind: "bar", unit: "count", x: "date",
        definition: `Accounts created in each ${w.bucket}. Deleted accounts are not counted.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `${r.count(n, "person", "people")} signed up ${r.when}.`;
        },
        query: perBucket(sql, w, profiles, count),
    };
    const opensChart: AdminDashboardChartDefinition = {
        id: "opens_per_bucket", title: `App opens ${per}`, kind: "bar", unit: "count", x: "date",
        definition: `How many times people opened the app in each ${w.bucket}. The refresh right after a background sync is not an open.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `The app was opened ${r.count(n, "time", "times")} ${r.when}.`;
        },
        query: perBucket(sql, w, opens, count, { gaps: true }),
    };
    const fightsCreatedChart: AdminDashboardChartDefinition = {
        id: "fights_created_per_bucket", title: `Fights created ${per}`, kind: "bar", unit: "count", x: "date",
        definition: `New Fights created in each ${w.bucket}. Later rounds of a repeating Fight, the app-wide Fight and suggested Fights are not counted.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `${r.count(n, "new fight was", "new fights were")} created ${r.when}.`;
        },
        note: "New Fights, not later rounds. App-wide and suggested Fights excluded.",
        query: perBucket(sql, w, firstRounds, count),
    };
    const stepsChart: AdminDashboardChartDefinition = {
        id: "steps_per_bucket", title: `Steps ${per}`, kind: "bar", unit: "steps", x: "date",
        definition: `Steps from Apple Health in each ${w.bucket}, added up for everyone. Only complete days, from each person's signup day.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `FitFight people walked ${r.format(n)} steps ${r.when}.`;
        },
        note: "Complete days since each person joined, through yesterday.",
        query: perBucket(sql, w, recentSteps, sql`sum(e.steps)`, { complete: true }),
    };

    switch (section) {
        case "overview":
            return {
                cards: [
                    totalUsers, weeklyActive, monthlyActive, weeklyNewUsers, weeklyFightsCreated, liveFights,
                    weeklySteps,
                    {
                        id: "health_connected", title: "Apple Health connected", unit: "count", better: true,
                        note: "People with Apple Health connected now, vs 7 days ago.",
                        query: sql`
                            select count(distinct user_id)::float8 as value,
                                count(distinct user_id) filter (where connected_at < ${ago(7)})::float8 as previous
                            from public.data_sources where provider = 'apple_health' and revoked_at is null
                        `,
                    },
                ],
                charts: [
                    totalUsersChart, newUsersChart,
                    {
                        id: "active_users_per_bucket", title: `Active users ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `People who opened the app at least once in each ${w.bucket}. Each person counts once per ${w.bucket}. A background sync without an open does not count.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} opened the app ${r.when}.`;
                        },
                        note: `Distinct people who opened the app in each ${w.bucket}.`,
                        query: perBucket(sql, w, activity, people, { gaps: true }),
                    },
                    fightsCreatedChart, stepsChart, opensChart,
                ],
            };
        case "users":
            return {
                cards: [
                    totalUsers, weeklyNewUsers,
                    {
                        id: "monthly_new_users", title: "Monthly new users", unit: "count", better: true,
                        note: "Last 30 days vs the 30 before.",
                        query: eventCard(sql, w, 30, profiles, count),
                    },
                    ...[
                        { id: "onboarding_rate", title: "Monthly username rate", did: "picked a username", condition: sql`p.handle_set_at is not null` },
                        { id: "health_rate", title: "Monthly Health connect rate", did: "connected Apple Health", condition: sql`exists (
                            select 1 from public.data_sources as s
                            where s.user_id = p.user_id and s.provider = 'apple_health')` },
                        { id: "fight_rate", title: "Monthly fight join rate", did: "joined a fight", condition: sql`exists (
                            select 1 from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                            where m.user_id = p.user_id and m.state = 'accepted')` },
                        { id: "referral_rate", title: "Monthly referral rate", did: "came from a referral", condition: sql`exists (
                            select 1 from private.referrals as r where r.referred_user_id = p.user_id)` },
                    ].map(({ id, title, did, condition }): AdminDashboardCardDefinition => ({
                        id, title, unit: "percent", better: true,
                        note: `Share of the last 30 days' signups who ${did}, vs the 30 days before.`,
                        query: sql`
                            select 100.0 * count(*) filter (where p.created_at >= ${ago(30)} and ${condition})
                                    / nullif(count(*) filter (where p.created_at >= ${ago(30)}), 0) as value,
                                100.0 * count(*) filter (where p.created_at < ${ago(30)} and ${condition})
                                    / nullif(count(*) filter (where p.created_at < ${ago(30)}), 0) as previous
                            from public.profiles as p
                            where p.deleted_at is null and p.created_at >= ${ago(60)} and p.created_at < ${w.now}
                        `,
                    })),
                    {
                        id: "days_to_first_fight", title: "Monthly days to first fight", unit: "days", better: false,
                        note: "Median, for the last 30 days' signups who joined a fight, vs the 30 days before.",
                        query: eventCard(sql, w, 30, sql`
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
                        id: "referrals", title: "Monthly referrals", unit: "count", better: true,
                        note: "Last 30 days vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`
                            select referrer_user_id as user_id, created_at as at from private.referrals
                        `, count),
                    },
                ],
                charts: [
                    ...[
                        { id: "user_growth_wow", title: "Week-over-week user growth", span: 7, name: "week" },
                        { id: "user_growth_mom", title: "Month-over-month user growth", span: 30, name: "month" },
                    ].map(({ id, title, span, name }): AdminDashboardChartDefinition => ({
                        id, title, kind: "line", unit: "percent", x: "date",
                        definition: `How much the number of users grew in the ${span} days up to the end of each ${w.bucket}: total users then against total users ${span} days earlier.`,
                        example: (r) => {
                            const growth = r.latest();
                            return growth === undefined ? null
                                : `Total users ${growth >= 0 ? "grew" : "fell"} by ${r.format(Math.abs(growth))} in the last ${span} days.`;
                        },
                        note: `Total users at the end of each ${w.bucket} against ${span} days earlier, so each point is that ${name}'s growth.`,
                        query: sql`
                            select point.bucket::text as x,
                                (100.0 * count(*) filter (where p.joined_day <= point.day)
                                    / count(*) filter (where p.joined_day <= point.day - ${span}::int) - 100)::float8 as y
                            from (${samplePoints(sql, w)}) as point
                            cross join (${profiles}) as p
                            group by point.bucket, point.day
                            having count(*) filter (where p.joined_day <= point.day - ${span}::int) > 0
                            order by point.bucket
                        `,
                    })),
                    newUsersChart, totalUsersChart,
                    {
                        id: "onboarding_by_signup", title: `Onboarding by signup ${w.bucket}`, kind: "line", unit: "percent", x: "date",
                        definition: `For the people who signed up in each ${w.bucket}: the share who picked a username, connected Apple Health and joined a fight, as of now. Recent signups have had less time, so their shares can still grow.`,
                        example: (r) => {
                            const name = r.at("Picked a username");
                            const health = r.at("Connected Apple Health");
                            const fight = r.at("Joined a fight");
                            if (name === undefined || health === undefined || fight === undefined) return null;
                            return `Of the people who signed up ${r.when}, ${r.format(name)} picked a username, ${r.format(health)} connected Apple Health and ${r.format(fight)} joined a fight.`;
                        },
                        note: `Share of each ${w.bucket}'s signups who did each step, as of now. Recent signups have had less time.`,
                        query: perBucket(sql, w, sql`
                            select p.at, step.series, step.done
                            from (${profiles}) as p
                            cross join lateral (values
                                ('Picked a username', p.handle_set_at is not null),
                                ('Connected Apple Health', exists (
                                    select 1 from public.data_sources as s
                                    where s.user_id = p.user_id and s.provider = 'apple_health')),
                                ('Joined a fight', exists (
                                    select 1 from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted'))
                            ) as step(series, done)
                        `, sql`avg(case when e.done then 100.0 else 0 end)`, {
                            gaps: true, series: ["Picked a username", "Connected Apple Health", "Joined a fight"],
                        }),
                    },
                    {
                        id: "referrals_per_bucket", title: `Referrals ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Signups that came through someone's referral link, in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} joined through a referral ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`select created_at as at from private.referrals`, count),
                    },
                    ...[
                        { id: "funnel_period", title: "Onboarding funnel, last 30 days' signups", who: "the people who signed up in the last 30 days", scope: sql`p.created_at >= ${ago(30)}` },
                        { id: "funnel_all", title: "Onboarding funnel, all users", who: "all users", scope: sql`true` },
                    ].map(({ id, title, who, scope }): AdminDashboardChartDefinition => ({
                        id, title, kind: "bar", unit: "count", x: "label",
                        definition: `How far ${who} got: picking a username, connecting Apple Health, joining a first fight, finishing one and joining a second.`,
                        example: (r) => {
                            const signed = r.row("Signed up");
                            const joined = r.row("Joined a fight");
                            const finished = r.row("Finished a fight");
                            if (signed === undefined || joined === undefined || finished === undefined) return null;
                            const part = r.share(joined, signed);
                            return part ? `Of ${who} (${r.format(signed)}), ${part} joined a fight and ${r.share(finished, signed)} finished one.` : null;
                        },
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
                        id: "sign_in_methods", title: "Sign-in method, all users", kind: "bar", unit: "count", x: "label",
                        definition: "How people sign in. Apple means an Apple sign-in is on file; older Apple logins without one count as Google or other.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "user", "users")}, ${r.top.share} of everyone.` : null),
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
                        id: "languages", title: "App language, all users", kind: "bar", unit: "count", x: "label",
                        definition: "The language each person chose for the app. Follows iPhone means they kept the iPhone's language.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "user", "users")}, ${r.top.share} of everyone.` : null),
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
                        id: "time_zones", title: "Top time zones, all users", kind: "bar", unit: "count", x: "label",
                        definition: "Each person's saved time zone, a rough guide to where they live.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.share} of users are in ${r.top.x} (${r.format(r.top.y)}).` : null),
                        query: sql`
                            select coalesce(time_zone, 'Unknown') as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 2 desc, 1 limit 12
                        `,
                    },
                    {
                        id: "companions", title: "Companion choices, all users", kind: "bar", unit: "count", x: "label",
                        definition: "The companion each person picked. None yet means they have not picked one.",
                        example: (r) => {
                            const pick = r.rows.find((row) => row.x !== "None yet" && row.y > 0);
                            return pick ? `${pick.x} is the most picked companion: ${r.count(pick.y, "user", "users")}.` : null;
                        },
                        query: sql`
                            select coalesce(initcap(replace(companion_id, '-', ' ')), 'None yet') as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null group by 1 order by 2 desc, 1 limit 15
                        `,
                    },
                    {
                        id: "top_referrers", title: "Top referrers, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People whose referral links brought the most signups, all time.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} brought ${r.count(r.top.y, "person", "people")} to FitFight.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from private.referrals as r join public.profiles as p on p.user_id = r.referrer_user_id
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                ],
            };
        case "retention": {
            // NOTE: retention follows people who connected Apple Health. Their phones sync steps
            // in the background, opened or not, until the app is deleted or Health is turned off.
            // App opens can't be used while servers still delete them after 7 days. The floor
            // covers the last 6 signup months, the cards' cohorts and the chart period.
            const synced = sql`
                select distinct history.user_id, history.day
                from (${stepHistory(sql`least(${w.start}::date, ${w.today}::date - 200)`)}) as history
                where history.day >= history.joined_day
            `;
            const withHealth = sql`
                select p.user_id, p.joined_day, p.at from (${profiles}) as p
                where exists (
                    select 1 from public.data_sources as s where s.user_id = p.user_id and s.provider = 'apple_health'
                )
            `;
            // Signups of the `span` days that just got past day `to` after signing up, against the
            // `span` days before them: the share who synced steps `from` to `to` days after.
            const rate = (from: number, to: number, span: number) => sql`
                with active as materialized (${synced}),
                eligible as (
                    select c.user_id, c.joined_day, c.joined_day < ${w.today}::date - ${to + span}::int as previous
                    from (${withHealth}) as c
                    where c.joined_day >= ${w.today}::date - ${to + 2 * span}::int
                        and c.joined_day < ${w.today}::date - ${to}::int
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
            const cohort = w.bucket === "month" ? "month" : "week";
            return {
                cards: [
                    {
                        id: "signups_with_health", title: "Monthly signups with Health", unit: "count", better: true,
                        note: "The people retention follows. The 30 days before today vs the 30 before.",
                        query: sql`
                            select count(*) filter (where c.joined_day >= ${w.today}::date - 30)::float8 as value,
                                count(*) filter (where c.joined_day < ${w.today}::date - 30)::float8 as previous
                            from (${withHealth}) as c
                            where c.joined_day >= ${w.today}::date - 60 and c.joined_day < ${w.today}::date
                        `,
                    },
                    ...[
                        { id: "week_1", title: "Week 1 retention", from: 7, to: 13, span: 28 },
                        { id: "week_2", title: "Week 2 retention", from: 14, to: 20, span: 28 },
                        { id: "week_4", title: "Week 4 retention", from: 28, to: 34, span: 28 },
                        { id: "month_1", title: "Month 1 retention", from: 30, to: 59, span: 30 },
                        { id: "month_3", title: "Month 3 retention", from: 90, to: 119, span: 30 },
                    ].map(({ id, title, from, to, span }): AdminDashboardCardDefinition => ({
                        id, title, unit: "percent", better: true,
                        note: `Phone synced steps on days ${from} to ${to} after signup. Latest ${span} days of signups to get there, vs the ${span} before.`,
                        query: rate(from, to, span),
                    })),
                ],
                charts: [
                    {
                        id: "weekly_cohorts", title: "Retention curves, last 8 signup weeks", kind: "line", unit: "percent", x: "label",
                        definition: "One line per signup week. Each point is the share of that week's signups with Apple Health whose phone still synced steps N weeks later. W0 is their first week and W1 their second.",
                        example: (r) => {
                            const cohort = r.series.find((line) => line.points.some((point) => point.x === "W1"));
                            const kept = cohort?.points.find((point) => point.x === "W1");
                            return cohort && kept
                                ? `Of the people who signed up in the ${cohort.name.replace("Week of", "week of")}, ${r.format(kept.y)} still synced steps in their second week.`
                                : null;
                        },
                        note: "One line per signup week. W1 is the share whose phone still synced steps 7 to 13 days after signing up.",
                        query: curves("week", 8),
                    },
                    {
                        id: "monthly_cohorts", title: "Retention curves, last 6 signup months", kind: "line", unit: "percent", x: "label",
                        definition: "One line per signup month. Each point is the share of that month's signups with Apple Health whose phone still synced steps N months later, in 30-day blocks. M0 is their first month.",
                        example: (r) => {
                            const cohort = r.series.find((line) => line.points.some((point) => point.x === "M1"));
                            const kept = cohort?.points.find((point) => point.x === "M1");
                            return cohort && kept
                                ? `Of the people who signed up in ${cohort.name}, ${r.format(kept.y)} still synced steps in their second month.`
                                : null;
                        },
                        note: "One line per signup month. M1 is days 30 to 59 after signing up.",
                        query: curves("month", 6),
                    },
                    {
                        id: "retention_by_signup", title: `Retention by signup ${cohort}`, kind: "line", unit: "percent", x: "date",
                        definition: `For each signup ${cohort}: the share of people with Apple Health whose phone still synced steps in week 1 (days 7 to 13) and week 4 (days 28 to 34) after signing up. It shows if newer signups stay longer.`,
                        example: (r) => {
                            const week = r.series.find((line) => line.name === "Week 1")?.points.at(-1);
                            return week
                                ? `Of the people who signed up in the ${cohort} starting ${r.day(week.x)}, ${r.format(week.y)} still synced steps in week 1.`
                                : null;
                        },
                        note: `Share of each signup ${cohort}'s people with Apple Health whose phone still synced steps in week 1 (days 7 to 13) and week 4 (days 28 to 34). People count once they get there.`,
                        query: sql`
                            with active as materialized (${synced}),
                            cohort as (
                                select h.user_id, h.joined_day, date_trunc(${cohort}::text, h.joined_day::timestamp)::date as bucket
                                from (${withHealth}) as h
                                where h.joined_day >= date_trunc(${cohort}::text, ${w.start}::timestamp)::date
                            ),
                            measured as (
                                select c.bucket, k.series, k.position,
                                    100.0 * count(*) filter (where exists (
                                        select 1 from active as a
                                        where a.user_id = c.user_id and a.day between c.joined_day + k.low and c.joined_day + k.high
                                    )) / count(*) as y
                                from cohort as c
                                cross join (values ('Week 1', 1, 7, 13), ('Week 4', 2, 28, 34)) as k(series, position, low, high)
                                where c.joined_day + k.high < ${w.today}::date
                                group by c.bucket, k.series, k.position
                            )
                            select bucket::text as x, y::float8 as y, series from measured order by position, bucket
                        `,
                    },
                    {
                        id: "health_signups_per_bucket", title: `Signups with Apple Health ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Signups who connected Apple Health, in each ${w.bucket}. These are the people retention follows.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} signed up and connected Apple Health ${r.when}.`;
                        },
                        note: "The people retention follows.",
                        query: perBucket(sql, w, withHealth, count),
                    },
                ],
            };
        }
        case "engagement": {
            // Fixed 120 days, so these don't move with the chart period.
            const seen = activitySince(sql`${ago(120)}`);
            return {
                cards: [
                    {
                        id: "daily_active", title: "Daily active users", unit: "count", better: true,
                        note: "Opened the app in the last 24 hours, vs the 24 before.",
                        query: eventCard(sql, w, 1, activity, people),
                    },
                    weeklyActive, monthlyActive,
                    {
                        id: "stickiness", title: "Monthly stickiness", unit: "percent", better: true,
                        note: "Average daily actives divided by monthly actives, last 30 days vs the 30 before.",
                        query: sql`
                            select 100.0 * (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${ago(30)}) / 30.0)
                                    / nullif(count(distinct e.user_id) filter (where e.at >= ${ago(30)}), 0) as value,
                                100.0 * (count(distinct (e.user_id, (e.at at time zone 'Europe/Paris')::date)) filter (
                                    where e.at >= ${ago(60)} and e.at < ${ago(30)}) / 30.0)
                                    / nullif(count(distinct e.user_id) filter (
                                        where e.at >= ${ago(60)} and e.at < ${ago(30)}), 0) as previous
                            from (${activity}) as e where e.at < ${w.now}
                        `,
                    },
                    weeklyOpens,
                    {
                        id: "opens_per_active", title: "Weekly opens per active user", unit: "count", better: true,
                        note: "App opens divided by people who opened the app, last 7 days vs the 7 before.",
                        query: sql`
                            select count(*) filter (where e.trigger = 'foreground' and e.at >= ${ago(7)})::float8
                                    / nullif(count(distinct e.user_id) filter (where e.at >= ${ago(7)}), 0) as value,
                                count(*) filter (where e.trigger = 'foreground' and e.at >= ${ago(14)} and e.at < ${ago(7)})::float8
                                    / nullif(count(distinct e.user_id) filter (where e.at >= ${ago(14)} and e.at < ${ago(7)}), 0)
                                    as previous
                            from (${activity}) as e where e.at < ${w.now}
                        `,
                    },
                    {
                        id: "returning", title: "Weekly return rate", unit: "percent", better: true,
                        note: "Share of the previous 7 days' active people who were active again in the last 7.",
                        query: sql`
                            with periods as (
                                select distinct e.user_id,
                                    case when e.at >= ${ago(7)} then 0 when e.at >= ${ago(14)} then 1 else 2 end as period
                                from (${activity}) as e where e.at >= ${ago(21)} and e.at < ${w.now}
                            )
                            select 100.0 * count(*) filter (where p.period = 1 and exists (
                                        select 1 from periods as q where q.user_id = p.user_id and q.period = 0))
                                    / nullif(count(*) filter (where p.period = 1), 0) as value,
                                100.0 * count(*) filter (where p.period = 2 and exists (
                                        select 1 from periods as q where q.user_id = p.user_id and q.period = 1))
                                    / nullif(count(*) filter (where p.period = 2), 0) as previous
                            from periods as p
                        `,
                    },
                    {
                        id: "lapsed", title: "Lapsed for 14+ days", unit: "count", better: false,
                        note: "Opened the app before, not in the last 14 days. Now vs 7 days ago.",
                        query: sql`
                            with last_open as (
                                select user_id, max(at) as now_last, max(at) filter (where at < ${ago(7)}) as week_ago_last
                                from (${seen}) as e where e.at < ${w.now} group by user_id
                            )
                            select count(*) filter (where now_last < ${ago(14)})::float8 as value,
                                count(*) filter (where week_ago_last < ${ago(21)})::float8 as previous
                            from last_open
                        `,
                    },
                    {
                        id: "active_days", title: "Monthly active days", unit: "days", better: true,
                        note: "Average days each active person opened the app, last 30 days vs the 30 before.",
                        query: sql`
                            with windows as (
                                select case when e.day > ${w.today}::date - 30 then 'value' else 'previous' end as period,
                                    e.user_id
                                from (${activeDays}) as e
                                where e.day > ${w.today}::date - 60
                            )
                            select (count(*) filter (where period = 'value'))::float8
                                    / nullif(count(distinct user_id) filter (where period = 'value'), 0) as value,
                                (count(*) filter (where period = 'previous'))::float8
                                    / nullif(count(distinct user_id) filter (where period = 'previous'), 0) as previous
                            from windows
                        `,
                    },
                ],
                charts: [
                    {
                        id: "dau_wau_mau", title: "Daily, weekly and monthly active users", kind: "line", unit: "count", x: "date",
                        definition: w.bucket === "day"
                            ? "DAU: people who opened the app that day. WAU and MAU: people who opened it at least once in the 7 or 30 days up to that day."
                            : `DAU: people who opened the app on a day, averaged over the days of each ${w.bucket}. WAU and MAU: people who opened it at least once in the 7 or 30 days up to the end of the ${w.bucket}.`,
                        example: (r) => {
                            const daily = r.at("DAU");
                            const weekly = r.at("WAU");
                            const monthly = r.at("MAU");
                            if (daily === undefined || weekly === undefined || monthly === undefined) return null;
                            const opened = w.bucket === "day"
                                ? `${r.count(daily, "person", "people")} opened the app ${r.when}`
                                : `${r.format(daily)} people opened the app on an average day ${r.when}`;
                            return `${opened}. ${r.format(weekly)} opened it in the 7 days up to then, and ${r.format(monthly)} in the 30 days.`;
                        },
                        note: w.bucket === "day"
                            ? "WAU and MAU count the 7 and 30 days up to each day."
                            : `DAU is the daily average in each ${w.bucket}. WAU and MAU count the 7 and 30 days up to its end, now for the last one.`,
                        query: sql`
                            with active as materialized (${activeDays}), point as (${samplePoints(sql, w)}), counted as (
                                select point.bucket, point.day,
                                    count(a.user_id) filter (where a.day >= point.bucket)::float8
                                        / (point.day - greatest(point.bucket, (select min(day) from active)) + 1) as daily,
                                    count(distinct a.user_id) filter (where a.day > point.day - 7) as weekly,
                                    count(distinct a.user_id) filter (where a.day > point.day - 30) as monthly
                                from point left join active as a
                                    on a.day <= point.day and a.day > least(point.day - 30, point.bucket - 1)
                                group by point.bucket, point.day
                            )
                            select counted.bucket::text as x, value.y::float8 as y, value.series
                            from counted cross join lateral (values
                                (1, 'DAU', counted.daily), (2, 'WAU', counted.weekly), (3, 'MAU', counted.monthly)
                            ) as value(position, series, y)
                            where counted.day >= (select min(day) from active)
                            order by value.position, counted.bucket
                        `,
                    },
                    opensChart,
                    {
                        id: "opens_per_active_person", title: `Opens per active user ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `App opens divided by the people who opened the app, in each ${w.bucket}. It shows how often an active person comes back.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `Each active person opened the app ${r.count(n, "time", "times")} on average ${r.when}.`;
                        },
                        note: `App opens divided by people who opened the app in each ${w.bucket}.`,
                        query: perBucket(sql, w, activity, sql`
                            count(*) filter (where e.trigger = 'foreground')::float8 / nullif(count(distinct e.user_id), 0)
                        `, { gaps: true }),
                    },
                    {
                        id: "new_vs_returning", title: `New vs returning active users ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `People who opened the app in each ${w.bucket}, split into new (signed up in that same ${w.bucket}) and returning (everyone else).`,
                        example: (r) => {
                            const back = r.at("Returning");
                            const fresh = r.at("New") ?? 0;
                            return back === undefined ? null
                                : `${r.count(back, "returning person", "returning people")} and ${r.count(fresh, "new person", "new people")} opened the app ${r.when}.`;
                        },
                        note: `New: signed up in the same ${w.bucket}.`,
                        query: perBucket(sql, w, sql`
                            select a.user_id, a.at, case when date_trunc(${w.bucket}::text, p.joined_day::timestamp)
                                = date_trunc(${w.bucket}::text, (a.at at time zone 'Europe/Paris')::date::timestamp)
                                then 'New' else 'Returning' end as series
                            from (${activity}) as a join (${profiles}) as p using (user_id)
                        `, people, { gaps: true, series: ["New", "Returning"] }),
                    },
                    {
                        id: "opens_percentiles", title: "Opens per person per day: P50 and P90", kind: "line", unit: "count", x: "date",
                        definition: "How many times people opened the app on the days they opened it. P50 is the typical person; only 10% opened it more often than P90.",
                        example: (r) => {
                            const typical = r.at("P50");
                            const top = r.at("P90");
                            return typical === undefined || top === undefined ? null
                                : `The typical active person opened the app ${r.count(typical, "time", "times")} a day ${r.when}, and the top 10% ${r.count(top, "time", "times")} or more.`;
                        },
                        note: `Among people who opened the app that day${w.bucket === "day" ? "" : `, across each ${w.bucket}`}.`,
                        query: sql`
                            with daily as (
                                select user_id, (at at time zone 'Europe/Paris')::date as day, count(*) as opens
                                from (${opens}) as opens
                                where (at at time zone 'Europe/Paris')::date >= ${w.start}::date
                                group by 1, 2
                            ), bucketed as (
                                select date_trunc(${w.bucket}::text, day::timestamp)::date as bucket,
                                    percentile_cont(0.5) within group (order by opens) as p50,
                                    percentile_cont(0.9) within group (order by opens) as p90
                                from daily group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values (1, 'P50', bucketed.p50), (2, 'P90', bucketed.p90))
                                as value(position, series, y)
                            order by value.position, bucketed.bucket
                        `,
                    },
                    {
                        id: "power_users", title: "Active days in the last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "People by how many of the last 30 days they opened the app. The more people in the higher groups, the stronger the habit.",
                        example: (r) => {
                            const regular = (r.row("15-21") ?? 0) + (r.row("22-30") ?? 0);
                            return r.total > 0
                                ? `${r.count(regular, "person", "people")} opened the app on 15 or more of the last 30 days, out of ${r.format(r.total)} who opened it at all.`
                                : null;
                        },
                        note: "People by how many of the last 30 days they opened the app.",
                        query: sql`
                            with per_person as (
                                select user_id, count(*) as days from (${activeDays}) as a
                                where a.day > ${w.today}::date - 30 group by 1
                            )
                            select band.x, count(per_person.days)::float8 as y from (values
                                (1, '1 day', 1, 1), (2, '2-3', 2, 3), (3, '4-7', 4, 7),
                                (4, '8-14', 8, 14), (5, '15-21', 15, 21), (6, '22-30', 22, 30)
                            ) as band(position, x, low, high)
                            left join per_person on per_person.days between band.low and band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "recency", title: "Days since last open, all users", kind: "bar", unit: "count", x: "label",
                        definition: "Every user by the days since they last opened the app. Never means no open recorded in the last 120 days.",
                        example: (r) => {
                            const today = r.row("Today") ?? 0;
                            const never = r.row("Never") ?? 0;
                            return r.total > 0
                                ? `${r.count(today, "person", "people")} opened the app today, and ${r.format(never)} have no open in the last 120 days.`
                                : null;
                        },
                        note: "Never: no open recorded in the last 120 days.",
                        query: sql`
                            with seen_days as (
                                select distinct user_id, (at at time zone 'Europe/Paris')::date as day from (${seen}) as a
                            ), last_open as (
                                select p.user_id, ${w.today}::date - max(s.day) as days
                                from public.profiles as p left join seen_days as s using (user_id)
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
                        id: "opens_heatmap", title: "When people open the app, last 30 days", kind: "heatmap", unit: "count", x: "label",
                        definition: "App opens in the last 30 days by weekday and hour, Paris time. The darker the cell, the more opens.",
                        example: (r) => (r.peak && r.peak.value > 0
                            ? `The busiest hour is ${r.peak.y} ${r.peak.x}:00 Paris time, with ${r.count(r.peak.value, "open", "opens")} in 30 days.`
                            : null),
                        note: "Opens by weekday and hour, Paris time.",
                        query: sql`
                            with counted as (
                                select extract(isodow from o.at at time zone 'Europe/Paris')::int as d,
                                    extract(hour from o.at at time zone 'Europe/Paris')::int as h, count(*) as n
                                from (${opens}) as o
                                where o.at >= ${ago(30)} and o.at < ${w.now}
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
                        id: "top_openers", title: "Most app opens, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "People who opened the app the most in the last 30 days.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} opened the app ${r.count(r.top.y, "time", "times")} in the last 30 days.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from (${opens}) as o join public.profiles as p on p.user_id = o.user_id
                            where o.at >= ${ago(30)} and o.at < ${w.now}
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                ],
            };
        }
        case "steps":
            return {
                cards: [
                    weeklySteps,
                    {
                        id: "average_steps", title: "Weekly avg daily steps", unit: "steps", better: true,
                        note: "Per person-day, the 7 complete days before today vs the 7 before.",
                        query: dayCard(sql, w, 7, recentSteps, sql`avg(e.steps)`),
                    },
                    {
                        id: "median_steps", title: "Weekly median daily steps", unit: "steps", better: true,
                        note: "Per person-day, the 7 complete days before today vs the 7 before.",
                        query: dayCard(sql, w, 7, recentSteps, sql`percentile_cont(0.5) within group (order by e.steps)`),
                    },
                    {
                        id: "walkers", title: "Weekly walkers", unit: "count", better: true,
                        note: "People with step data in the 7 days before today, vs the 7 before.",
                        query: dayCard(sql, w, 7, recentSteps, people),
                    },
                    {
                        id: "ten_k_days", title: "Weekly 10K-step days", unit: "percent", better: true,
                        note: "Share of person-days with 10,000 steps or more, last 7 days vs the 7 before.",
                        query: dayCard(sql, w, 7, recentSteps, sql`avg(case when e.steps >= 10000 then 100.0 else 0 end)`),
                    },
                    {
                        id: "fight_day_lift", title: "Monthly fight-day lift", unit: "percent", better: true,
                        note: "Extra steps on days in a live Fight vs other days. Last 30 days vs the 30 before.",
                        query: sql`
                            with windows as (
                                select case when e.day >= ${w.today}::date - 30 then 'value' else 'previous' end as period,
                                    e.steps, e.in_fight
                                from (${fightDays}) as e
                                where e.day >= ${w.today}::date - 60
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
                        note: "All time. Median of each person's 4 weeks after signup vs the 4 before.",
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
                        id: "all_time_steps", title: "All-time steps", unit: "steps", better: true,
                        note: "Every complete day since each person joined. Now vs 7 days ago.",
                        query: sql`
                            select sum(e.steps)::float8 as value,
                                sum(e.steps) filter (where e.day < ${w.today}::date - 7)::float8 as previous
                            from (${steps}) as e
                        `,
                    },
                ],
                charts: [
                    stepsChart,
                    {
                        id: "mean_median", title: "Steps per person per day: mean and median", kind: "line", unit: "steps", x: "date",
                        definition: "Steps per person per day. The mean is the average; the median is the middle person. When the mean is above the median, a few big walkers pull the average up.",
                        example: (r) => {
                            const mean = r.at("Mean");
                            const median = r.at("Median");
                            return mean === undefined || median === undefined ? null
                                : `The average person walked ${r.format(mean)} steps a day ${r.when}, and the middle person ${r.format(median)}.`;
                        },
                        note: `${w.bucket === "day" ? "" : `Over the person-days in each ${w.bucket}. `}A gap means a few big walkers pull the mean up.`,
                        query: sql`
                            with bucketed as (
                                select date_trunc(${w.bucket}::text, s.day::timestamp)::date as bucket,
                                    avg(s.steps) as mean, percentile_cont(0.5) within group (order by s.steps) as median
                                from (${recentSteps}) as s
                                where s.day >= ${w.start}::date
                                group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values (1, 'Mean', bucketed.mean), (2, 'Median', bucketed.median))
                                as value(position, series, y)
                            order by value.position, bucketed.bucket
                        `,
                    },
                    {
                        id: "walkers_per_bucket", title: `People with step data ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `People with at least one complete day of Apple Health steps in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} had step data ${r.when}.`;
                        },
                        query: perBucket(sql, w, recentSteps, people, { complete: true }),
                    },
                    {
                        id: "ten_k_share_per_bucket", title: "Days over 10K steps", kind: "line", unit: "percent", x: "date",
                        definition: w.bucket === "day"
                            ? "Share of people with step data who walked 10,000 steps or more that day."
                            : `Share of person-days with 10,000 steps or more in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            if (n === undefined) return null;
                            return w.bucket === "day"
                                ? `${r.format(n)} of people walked 10,000 steps or more ${r.when}.`
                                : `${r.format(n)} of person-days reached 10,000 steps ${r.when}.`;
                        },
                        note: w.bucket === "day" ? "Share of people with 10,000 steps or more that day." : `Share of person-days with 10,000 steps or more in each ${w.bucket}.`,
                        query: perBucket(sql, w, recentSteps, sql`avg(case when e.steps >= 10000 then 100.0 else 0 end)`, {
                            complete: true, gaps: true,
                        }),
                    },
                    {
                        id: "fight_vs_other_days", title: "Steps on fight days vs other days", kind: "line", unit: "steps", x: "date",
                        definition: "Average steps per person-day on days when the person was in a live Fight, against their days without one.",
                        example: (r) => {
                            const fighting = r.at("In a fight");
                            const other = r.at("Other days");
                            return fighting === undefined || other === undefined ? null
                                : `People in a fight walked ${r.format(fighting)} steps a day ${r.when}, against ${r.format(other)} on other days.`;
                        },
                        note: `Average steps per person-day${w.bucket === "day" ? "" : ` in each ${w.bucket}`}, on days in a live Fight vs days without one.`,
                        query: perBucket(sql, w, sql`
                            select d.*, case when d.in_fight then 'In a fight' else 'Other days' end as series
                            from (${fightDays}) as d
                        `, sql`avg(e.steps)`, { complete: true, gaps: true, series: ["In a fight", "Other days"] }),
                    },
                    {
                        id: "people_by_average", title: "People by daily average, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "People by their average daily steps over the last 30 complete days.",
                        example: (r) => {
                            const active = (r.row("10K-15K") ?? 0) + (r.row("15K+") ?? 0);
                            const part = r.share(active, r.total);
                            return part
                                ? `${r.count(active, "person averages", "people average")} 10,000 steps a day or more: ${part} of everyone with step data.`
                                : null;
                        },
                        query: sql`
                            with people as (
                                select user_id, avg(steps) as steps from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - 30 group by 1
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
                        id: "around_joining", title: "Steps around signup, all time", kind: "line", unit: "steps", x: "label",
                        definition: "Average steps per person on each day around signup, from Apple Health history. Day 0 is the signup day; negative days are before it.",
                        example: (r) => {
                            const mean = (low: number, high: number) => {
                                const days = r.rows.filter((row) => Number(row.x) >= low && Number(row.x) < high);
                                return days.length ? days.reduce((sum, row) => sum + row.y, 0) / days.length : undefined;
                            };
                            const before = mean(-7, 0);
                            const after = mean(0, 7);
                            return before === undefined || after === undefined ? null
                                : `People walked ${r.format(before)} steps a day in the week before signing up and ${r.format(after)} in their first week.`;
                        },
                        note: "Day 0 is the signup day. Average across everyone with Health history on each day.",
                        query: sql`
                            select (day - joined_day)::text as x, avg(steps)::float8 as y
                            from (${history}) as h
                            where day - joined_day between -28 and 28
                            group by day - joined_day order by day - joined_day
                        `,
                    },
                    {
                        id: "joining_change_distribution", title: "Change after joining, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People by how their average steps changed: the 4 weeks after signup against the 4 weeks before. Only people with 7 or more days of data on each side.",
                        example: (r) => {
                            const up = (r.row("Up 5-20%") ?? 0) + (r.row("Up 20%+") ?? 0);
                            return r.total > 0
                                ? `${r.count(up, "person walks", "people walk")} at least 5% more since joining, out of ${r.format(r.total)}.`
                                : null;
                        },
                        note: "People by their 4 weeks after signup vs the 4 weeks before (7+ days of data each side).",
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
                        id: "top_walkers", title: "Top walkers, last 7 days", kind: "bar", unit: "steps", x: "label",
                        definition: "People with the most steps in the 7 complete days before today.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} walked the most: ${r.format(r.top.y)} steps in 7 days.` : null),
                        query: sql`
                            select '@' || handle as x, sum(steps)::float8 as y from (${recentSteps}) as s
                            where s.day >= ${w.today}::date - 7
                            group by handle order by 2 desc, 1 limit 10
                        `,
                    },
                ],
            };
        case "fights": {
            // A day's state is read at its end, or now for today.
            const instants = sql`
                select point.bucket, least((point.day + 1)::timestamp at time zone 'Europe/Paris', ${w.now}::timestamptz) as at
                from (${samplePoints(sql, w)}) as point
            `;
            return {
                cards: [
                    liveFights, weeklyFightsCreated,
                    {
                        id: "rounds_finished", title: "Weekly rounds finished", unit: "count", better: true,
                        note: "Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, sql`select ends_at as at from public.fights where state = 'final'`, count),
                    },
                    {
                        id: "joins", title: "Weekly fight joins", unit: "count", better: true,
                        note: "People joining someone else's Fight, app-wide ones excluded. Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, joins, count),
                    },
                    {
                        id: "people_in_fights", title: "Users in a live fight", unit: "percent", better: true,
                        note: "Share of all users, now vs 7 days ago.",
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
                                        and f.starts_at <= ${ago(7)} and f.ends_at > ${ago(7)})
                                    / nullif((select count(*) from public.profiles
                                        where deleted_at is null and created_at < ${ago(7)}), 0) as previous
                        `,
                    },
                    {
                        id: "fighters_per_fight", title: "Monthly fighters per fight", unit: "count", better: true,
                        note: "Average accepted fighters in Fights that started in the last 30 days, vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`
                            select f.starts_at as at, (select count(*) from public.fight_members as m
                                where m.fight_id = f.id and m.state = 'accepted') as fighters
                            from (${realFights}) as f where f.state <> 'cancelled'
                        `, sql`avg(e.fighters)`),
                    },
                    {
                        id: "invite_acceptance", title: "Monthly invite acceptance", unit: "percent", better: true,
                        note: "Share of people invited in the last 30 days who are now in the Fight, vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`
                            select event.occurred_at as at, bool_or(m.state = 'accepted') as accepted
                            from private.fight_membership_events as event
                            join (${realFights}) as f on f.id = event.fight_id
                            left join public.fight_members as m on m.fight_id = event.fight_id and m.user_id = event.user_id
                            where event.state = 'invited' and event.occurred_at is not null
                            group by event.fight_id, event.user_id, event.occurred_at
                        `, sql`avg(case when e.accepted then 100.0 else 0 end)`),
                    },
                    {
                        id: "cancel_rate", title: "Monthly cancel rate", unit: "percent", better: false,
                        note: "Share of Fights starting in the last 30 days that were cancelled, vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`select starts_at as at, state from (${realFights}) as f`,
                            sql`avg(case when e.state = 'cancelled' then 100.0 else 0 end)`),
                    },
                    {
                        id: "recurring_share", title: "Monthly recurring share", unit: "percent", better: null,
                        note: "Share of new Fights created as recurring, last 30 days vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`
                            select series.created_at as at, series.recurring from public.fight_series as series
                            where series.join_code <> 'PGG7' and not series.suggested
                        `, sql`avg(case when e.recurring then 100.0 else 0 end)`),
                    },
                    {
                        id: "winning_margin", title: "Monthly winning margin", unit: "percent", better: null,
                        note: "Median lead of the winner over second place, Fights finished in the last 30 days vs the 30 before.",
                        query: eventCard(sql, w, 30, sql`
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
                    fightsCreatedChart,
                    {
                        id: "live_fights_over_time", title: "Live fights", kind: "line", unit: "count", x: "date",
                        definition: `Fights running at the end of each ${w.bucket}, and now for the last point. The app-wide Fight counts.`,
                        example: (r) => {
                            const n = r.latest();
                            return n === undefined ? null : `${r.count(n, "fight is", "fights are")} live now.`;
                        },
                        note: `At the end of each ${w.bucket}, now for the last one. App-wide Fight included.`,
                        query: sql`
                            select point.bucket::text as x, (
                                select count(*) from public.fights as f
                                where f.state not in ('draft', 'cancelled') and f.starts_at <= point.at and f.ends_at > point.at
                            )::float8 as y
                            from (${instants}) as point order by point.bucket
                        `,
                    },
                    {
                        id: "people_in_fights_over_time", title: "Users in a live fight", kind: "line", unit: "percent", x: "date",
                        definition: `Share of all users who are in a live Fight, at the end of each ${w.bucket} and now for the last point.`,
                        example: (r) => {
                            const n = r.latest();
                            return n === undefined ? null : `${r.format(n)} of users are in a live fight now.`;
                        },
                        note: `Share of all users, at the end of each ${w.bucket}, now for the last one.`,
                        query: sql`
                            select point.bucket::text as x, (100.0 * (
                                select count(distinct m.user_id) from public.fight_members as m
                                join public.fights as f on f.id = m.fight_id
                                where m.state = 'accepted' and f.state not in ('draft', 'cancelled')
                                    and f.starts_at <= point.at and f.ends_at > point.at
                            ) / users.total)::float8 as y
                            from (${instants}) as point
                            cross join lateral (
                                select count(*) as total from public.profiles where deleted_at is null and created_at < point.at
                            ) as users
                            where users.total > 0
                            order by point.bucket
                        `,
                    },
                    {
                        id: "rounds_finished_per_bucket", title: `Rounds finished ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Fight rounds that ended with results, in each ${w.bucket}. Every round of a repeating Fight counts.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "round", "rounds")} finished ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`select ends_at as at from public.fights where state = 'final'`, count),
                    },
                    {
                        id: "invites_and_joins", title: `Invites and joins ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `Invitations sent to Fights, and people who joined someone else's Fight, in each ${w.bucket}. App-wide and suggested Fights are not counted.`,
                        example: (r) => {
                            const sent = r.at("Invites sent");
                            const joined = r.at("People joining");
                            return sent === undefined || joined === undefined ? null
                                : `${r.count(sent, "invite was", "invites were")} sent ${r.when}, and ${r.count(joined, "person", "people")} joined a fight.`;
                        },
                        note: "App-wide and suggested Fights excluded.",
                        query: perBucket(sql, w, sql`
                            select event.occurred_at as at, 'Invites sent' as series
                            from private.fight_membership_events as event
                            join (${realFights}) as f on f.id = event.fight_id
                            where event.state = 'invited' and event.occurred_at is not null
                            union all
                            select joined.at, 'People joining' from (${joins}) as joined
                        `, count, { series: ["Invites sent", "People joining"] }),
                    },
                    {
                        id: "fight_sizes", title: "Fight sizes, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "Fights that started in the last 30 days, by their number of accepted fighters. Cancelled Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0
                            ? `${r.top.x}${/^\d/.test(r.top.x) ? " fighters" : ""} is the most common size: ${r.count(r.top.y, "fight", "fights")} out of ${r.format(r.total)}.`
                            : null),
                        note: "Fights that started in the last 30 days, by accepted fighters.",
                        query: sql`
                            with sizes as (
                                select (select count(*) from public.fight_members as m
                                    where m.fight_id = f.id and m.state = 'accepted') as fighters
                                from (${realFights}) as f
                                where f.state <> 'cancelled' and f.starts_at >= ${ago(30)} and f.starts_at < ${w.now}
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
                        definition: "How long Fights last, all time. App-wide and suggested Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} is the most common length: ${r.count(r.top.y, "fight", "fights")} out of ${r.format(r.total)}.` : null),
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
                        id: "margins", title: "How close fights end, all time", kind: "bar", unit: "count", x: "label",
                        definition: "Finished Fights with two or more fighters, by how far the winner was ahead of second place, as a share of the winner's steps.",
                        example: (r) => {
                            const close = r.row("Under 5%") ?? 0;
                            return r.total > 0
                                ? `${r.count(close, "fight was", "fights were")} won by less than 5%, out of ${r.format(r.total)} finished fights.`
                                : null;
                        },
                        note: "Winner's lead over second place, finished Fights.",
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
                        id: "time_to_first_fight", title: "Time from signup to first fight, all users", kind: "bar", unit: "count", x: "label",
                        definition: "Every user by the time between signing up and first joining a fight. Not yet means they have not joined one.",
                        example: (r) => {
                            const same = r.row("Same day") ?? 0;
                            const waiting = r.row("Not yet") ?? 0;
                            return r.total > 0
                                ? `${r.count(same, "person", "people")} joined a fight on the day they signed up, and ${r.format(waiting)} have not joined one yet.`
                                : null;
                        },
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
                        definition: "People who joined the most Fights, all time. App-wide and suggested Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} joined ${r.count(r.top.y, "fight", "fights")}.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from public.fight_members as m join (${realFights}) as f on f.id = m.fight_id
                            join public.profiles as p on p.user_id = m.user_id
                            where m.state = 'accepted' group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_winners", title: "Most wins, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People who won the most finished Fights that had at least two fighters, all time.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} won ${r.count(r.top.y, "fight", "fights")}.` : null),
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
                        id: "loser_actions", title: "Most common loser actions, all time", kind: "bar", unit: "count", x: "label",
                        definition: "The actions losers most often have to do, as people typed them, all time.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" is the most common action, in ${r.count(r.top.y, "fight", "fights")}.` : null),
                        query: sql`
                            select left(lower(trim(action_text)), 40) as x, count(*)::float8 as y
                            from public.fight_series where action_text is not null and trim(action_text) <> ''
                                and join_code <> 'PGG7' and not suggested
                            group by 1 order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "app_wide_members", title: "App-wide and suggested fights, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People in the app-wide and suggested Fights, across all their rounds.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} has ${r.count(r.top.y, "fighter", "fighters")}.` : null),
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
        }
        case "social": {
            const posts = sql`select author_id as user_id, created_at as at from public.fight_posts`;
            const comments = sql`select author_id as user_id, created_at as at from public.fight_post_comments`;
            const reactions = sql`select user_id, created_at as at, emoji from public.fight_post_reactions`;
            const friendships = sql`
                select requester_id as user_id, accepted_at as at from private.profile_friendships
                where state = 'accepted' and accepted_at is not null
            `;
            const weekly = "Last 7 days vs the 7 before.";
            return {
                cards: [
                    { id: "posts", title: "Weekly posts", unit: "count", better: true, note: weekly, query: eventCard(sql, w, 7, posts, count) },
                    { id: "comments", title: "Weekly comments", unit: "count", better: true, note: weekly, query: eventCard(sql, w, 7, comments, count) },
                    { id: "reactions", title: "Weekly reactions", unit: "count", better: true, note: weekly, query: eventCard(sql, w, 7, reactions, count) },
                    {
                        id: "posters", title: "Weekly people posting", unit: "count", better: true,
                        note: "Wrote a post or a comment in the last 7 days, vs the 7 before.",
                        query: eventCard(sql, w, 7, sql`${posts} union all ${comments}`, people),
                    },
                    {
                        id: "feedback_items", title: "Weekly bugs and requests", unit: "count", better: null, note: weekly,
                        query: eventCard(sql, w, 7, sql`select author_id as user_id, created_at as at from public.feedback_posts`, count),
                    },
                    {
                        id: "feedback_votes", title: "Weekly feedback votes", unit: "count", better: true, note: weekly,
                        query: eventCard(sql, w, 7, sql`select user_id, created_at as at from public.feedback_votes`, count),
                    },
                    {
                        id: "friendships", title: "Weekly new friendships", unit: "count", better: true, note: weekly,
                        query: eventCard(sql, w, 7, friendships, count),
                    },
                    {
                        id: "reports", title: "Weekly post reports", unit: "count", better: false, note: weekly,
                        query: eventCard(sql, w, 7, sql`select reporter_id as user_id, created_at as at from private.fight_post_reports`, count),
                    },
                ],
                charts: [
                    {
                        id: "social_activity", title: `Posts, comments and reactions ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `Posts, comments and reactions in Fight feeds, in each ${w.bucket}.`,
                        example: (r) => {
                            const posts = r.at("Posts");
                            const comments = r.at("Comments");
                            const reactions = r.at("Reactions");
                            if (posts === undefined || comments === undefined || reactions === undefined) return null;
                            return `People wrote ${r.count(posts, "post", "posts")} and ${r.count(comments, "comment", "comments")} and left ${r.count(reactions, "reaction", "reactions")} ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`
                            select at, 'Posts' as series from (${posts}) as post
                            union all select at, 'Comments' from (${comments}) as comment
                            union all select at, 'Reactions' from (${reactions}) as reaction
                        `, count, { series: ["Posts", "Comments", "Reactions"] }),
                    },
                    {
                        id: "friendships_per_bucket", title: `New friendships ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Friend requests that were accepted, in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "new friendship", "new friendships")} started ${r.when}.`;
                        },
                        query: perBucket(sql, w, friendships, count),
                    },
                    {
                        id: "feedback_per_bucket", title: `Bugs and requests ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `New bug reports and feature requests on the Feedback tab, in each ${w.bucket}.`,
                        example: (r) => {
                            const bugs = r.at("Bugs");
                            const requests = r.at("Requests");
                            return bugs === undefined || requests === undefined ? null
                                : `People filed ${r.count(bugs, "bug", "bugs")} and ${r.count(requests, "request", "requests")} ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`
                            select created_at as at, case kind when 'bug' then 'Bugs' else 'Requests' end as series
                            from public.feedback_posts
                        `, count, { series: ["Bugs", "Requests"] }),
                    },
                    {
                        id: "top_emojis", title: "Top reactions, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "The most used reactions in the last 30 days.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} is the most used reaction: ${r.count(r.top.y, "time", "times")} in 30 days.` : null),
                        query: sql`
                            select emoji as x, count(*)::float8 as y from (${reactions}) as r
                            where r.at >= ${ago(30)} and r.at < ${w.now} group by emoji order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_posters", title: "Most posts and comments, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "People with the most posts and comments in the last 30 days.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} wrote ${r.count(r.top.y, "post or comment", "posts and comments")} in the last 30 days.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from (${posts} union all ${comments}) as e join public.profiles as p on p.user_id = e.user_id
                            where e.at >= ${ago(30)} and e.at < ${w.now}
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_feedback", title: "Most voted open bugs and requests", kind: "bar", unit: "count", x: "label",
                        definition: "Open bugs and requests with the most votes.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" has the most votes: ${r.format(r.top.y)}.` : null),
                        query: sql`
                            select left(post.title, 40) as x, count(vote.user_id)::float8 as y
                            from public.feedback_posts as post
                            left join public.feedback_votes as vote on vote.post_id = post.id
                            where not post.archived group by post.id, post.title order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "posts_by_fight", title: "Fights with the most posts, all time", kind: "bar", unit: "count", x: "label",
                        definition: "Fights with the most posts in their feed, all time.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} has ${r.count(r.top.y, "post", "posts")}.` : null),
                        query: sql`
                            select left(f.name, 40) as x, count(*)::float8 as y
                            from public.fight_posts as post join public.fights as f on f.id = post.fight_id
                            group by f.id, f.name order by 2 desc, 1 limit 10
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
            const sent = sql`
                select user_id, coalesce(processed_at, created_at) as at, kind
                from private.notification_intents where status = 'sent'
            `;
            return {
                cards: [
                    {
                        id: "health_share", title: "Apple Health connected", unit: "percent", better: true,
                        note: "Share of users, now vs 7 days ago.",
                        query: sql`
                            select 100.0 * (select count(distinct user_id) from public.data_sources
                                    where provider = 'apple_health' and revoked_at is null and connected_at < ${w.now})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${w.now}), 0) as value,
                                100.0 * (select count(distinct user_id) from public.data_sources
                                    where provider = 'apple_health' and revoked_at is null and connected_at < ${ago(7)})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${ago(7)}), 0) as previous
                        `,
                    },
                    {
                        id: "sync_success", title: "Weekly sync success", unit: "percent", better: true,
                        note: "Share of syncs that succeeded, last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, attempts, sql`avg(case when e.outcome = 'succeeded' then 100.0 else 0 end)`),
                    },
                    {
                        id: "background_syncs", title: "Weekly background syncs", unit: "count", better: true,
                        note: "Syncs Apple Health started without an open. Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, sql`select * from (${attempts}) as a where a.trigger = 'observer'`, count),
                    },
                    {
                        id: "sync_time", title: "Weekly median sync time", unit: "seconds", better: false,
                        note: "Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, attempts, sql`percentile_cont(0.5) within group (order by e.total_ms / 1000.0)`),
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
                        id: "notifications_sent", title: "Weekly notifications sent", unit: "count", better: null,
                        note: "Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, sent, count),
                    },
                    {
                        id: "server_errors", title: "Weekly server errors", unit: "count", better: false,
                        note: "Last 7 days vs the 7 before.",
                        query: eventCard(sql, w, 7, errors, count),
                    },
                    {
                        id: "latest_build_share", title: "Weekly newest-build share", unit: "percent", better: true,
                        note: "Active people in the last 7 days whose latest build is the newest seen.",
                        query: sql`
                            with latest as (
                                select distinct on (user_id) user_id, app_build
                                from (${attempts}) as a where a.at >= ${ago(7)} and a.at < ${w.now}
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
                        id: "sync_issue_users", title: "Sync errors now", unit: "count", better: false,
                        note: "People whose latest sync report has an error.",
                        query: sql`
                            select count(*)::float8 as value, null::float8 as previous
                            from private.healthkit_sync_diagnostics where error_code is not null
                        `,
                    },
                ],
                charts: [
                    {
                        id: "sync_outcomes", title: `Sync outcomes ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Apple Health syncs in each ${w.bucket}, by result.`,
                        example: (r) => {
                            const ok = r.at("Succeeded") ?? 0;
                            const all = ok + (r.at("Failed") ?? 0) + (r.at("Cancelled") ?? 0);
                            const part = r.share(ok, all);
                            return part ? `${part} of syncs succeeded ${r.when}: ${r.format(ok)} of ${r.format(all)}.` : null;
                        },
                        query: perBucket(sql, w, sql`select at, initcap(outcome) as series from (${attempts}) as a`, count, {
                            gaps: true, series: ["Succeeded", "Failed", "Cancelled"],
                        }),
                    },
                    {
                        id: "sync_triggers", title: `Syncs by trigger ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: "Why each sync ran: Apple Health woke the app in the background, the app opened, or someone pulled to refresh.",
                        example: (r) => {
                            const background = r.at("Background") ?? 0;
                            const all = background + (r.at("App opened") ?? 0) + (r.at("Pull to refresh") ?? 0);
                            const part = r.share(background, all);
                            return part ? `${part} of syncs ran in the background ${r.when}: ${r.format(background)} of ${r.format(all)}.` : null;
                        },
                        query: perBucket(sql, w, sql`
                            select at, case trigger when 'foreground' then 'App opened' when 'observer' then 'Background'
                                else 'Pull to refresh' end as series
                            from (${attempts}) as a
                        `, count, { gaps: true, series: ["Background", "App opened", "Pull to refresh"] }),
                    },
                    {
                        id: "sync_durations", title: "Sync time: P50 and P90", kind: "line", unit: "seconds", x: "date",
                        definition: "How long a sync takes. P50 is the typical sync; only 10% take longer than P90.",
                        example: (r) => {
                            const typical = r.at("P50");
                            const slow = r.at("P90");
                            return typical === undefined || slow === undefined ? null
                                : `A typical sync took ${r.format(typical)} ${r.when}, and 10% took ${r.format(slow)} or more.`;
                        },
                        note: `Across each ${w.bucket}'s syncs.`,
                        query: sql`
                            with bucketed as (
                                select date_trunc(${w.bucket}::text, (at at time zone 'Europe/Paris')::date::timestamp)::date as bucket,
                                    percentile_cont(0.5) within group (order by total_ms / 1000.0) as p50,
                                    percentile_cont(0.9) within group (order by total_ms / 1000.0) as p90
                                from (${attempts}) as a
                                where (a.at at time zone 'Europe/Paris')::date >= ${w.start}::date group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral (values (1, 'P50', bucketed.p50), (2, 'P90', bucketed.p90))
                                as value(position, series, y)
                            order by value.position, bucketed.bucket
                        `,
                    },
                    {
                        id: "errors_per_bucket", title: `Server errors ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Server requests that failed with an error, in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `The server logged ${r.count(n, "error", "errors")} ${r.when}.`;
                        },
                        query: perBucket(sql, w, errors, count),
                    },
                    {
                        id: "notifications_per_bucket", title: `Notifications sent ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Push notifications the server sent, in each ${w.bucket}.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `The server sent ${r.count(n, "notification", "notifications")} ${r.when}.`;
                        },
                        query: perBucket(sql, w, sent, count),
                    },
                    {
                        id: "builds_in_use", title: "Builds in use, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "People by the newest app build they used in the last 7 days.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.count(r.top.y, "person uses", "people use")} ${r.top.x}: ${r.top.share} of people active in the last 7 days.` : null),
                        note: "People by the newest build they used.",
                        query: sql`
                            select version as x, count(*)::float8 as y from (
                                select distinct on (user_id) user_id, app_version || ' (' || app_build || ')' as version
                                from (${attempts}) as a where a.at >= ${ago(7)} and a.at < ${w.now}
                                order by user_id, a.at desc
                            ) as latest group by 1 order by 2 desc, 1 limit 12
                        `,
                    },
                    {
                        id: "sync_error_codes", title: "Sync errors by code, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "Failed syncs in the last 7 days, by error.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" is the most common sync error: ${r.count(r.top.y, "time", "times")} in 7 days.` : null),
                        query: sql`
                            select replace(error_code, '_', ' ') as x, count(*)::float8 as y
                            from (${attempts}) as a
                            where a.error_code is not null and a.at >= ${ago(7)} and a.at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "errors_by_path", title: "Server errors by route, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "Server errors in the last 7 days, by API route.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} failed the most: ${r.count(r.top.y, "error", "errors")} in 7 days.` : null),
                        query: sql`
                            select left(path, 48) as x, count(*)::float8 as y from (${errors}) as e
                            where e.at >= ${ago(7)} and e.at < ${w.now} group by 1 order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "notifications_by_kind", title: "Notifications sent by kind, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "Notifications sent in the last 7 days, by type.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" was sent the most: ${r.count(r.top.y, "time", "times")} in 7 days.` : null),
                        query: sql`
                            select replace(kind, '_', ' ') as x, count(*)::float8 as y from (${sent}) as n
                            where n.at >= ${ago(7)} and n.at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "notification_outcomes", title: "Notification outcomes, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "What happened to each notification in the last 7 days: sent, or skipped and why.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "notification", "notifications")}, ${r.top.share} of all.` : null),
                        query: sql`
                            select initcap(status) || coalesce(': ' || replace(skip_reason, '_', ' '), '') as x, count(*)::float8 as y
                            from private.notification_intents
                            where created_at >= ${ago(7)} and created_at < ${w.now}
                            group by 1 order by 2 desc limit 12
                        `,
                    },
                    {
                        id: "apns_results", title: "Apple push results, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "Apple's answer to each push delivery in the last 7 days. 200 means Apple accepted it.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "delivery", "deliveries")}, ${r.top.share} of all.` : null),
                        query: sql`
                            select coalesce(apns_http_status::text, 'No response') || coalesce(' ' || apns_reason, '') as x,
                                count(*)::float8 as y
                            from private.notification_deliveries
                            where coalesce(sent_at, created_at) >= ${ago(7)} and coalesce(sent_at, created_at) < ${w.now}
                            group by 1 order by 2 desc limit 10
                        `,
                    },
                    {
                        id: "push_permissions", title: "Push permission on devices, now", kind: "bar", unit: "count", x: "label",
                        definition: "Devices by notification permission, now.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "device", "devices")}, ${r.top.share} of all.` : null),
                        query: sql`
                            select initcap(replace(coalesce(permission_status, 'unknown'), '_', ' ')) as x, count(*)::float8 as y
                            from private.device_installations where revoked_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "background_refresh", title: "Background App Refresh, now", kind: "bar", unit: "count", x: "label",
                        definition: "Phones by their Background App Refresh setting, which background syncs need.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "phone", "phones")}, ${r.top.share} of all.` : null),
                        query: sql`
                            select initcap(coalesce(background_refresh_status, 'unknown')) as x, count(*)::float8 as y
                            from private.healthkit_sync_diagnostics group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "last_sync_age", title: "Time since last Apple Health sync, now", kind: "bar", unit: "count", x: "label",
                        definition: "Apple Health connections by the time since their last successful sync, now.",
                        example: (r) => {
                            const recent = (r.row("Under 1 hour") ?? 0) + (r.row("1-6 hours") ?? 0);
                            const part = r.share(recent, r.total);
                            return part
                                ? `${part} of Apple Health connections synced in the last 6 hours: ${r.format(recent)} of ${r.format(r.total)}.`
                                : null;
                        },
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
                ],
            };
        }
    }
}

/**
 * Operator-only aggregates, computed live from Postgres on every request.
 * Each card or chart is one query, so a failing query only marks its own tile.
 * `days` is the period of the charts over time; cards and other charts have fixed spans.
 */
export async function readAdminDashboard(
    section: AdminDashboardSection,
    days: number,
    environment: AdminDashboardEnvironment,
    database: Sql = createDatabaseClient(),
    bucket?: AdminDashboardBucket,
): Promise<AdminDashboard> {
    const now = new Date();
    const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris" }).format(now);
    // NOTE: charts start no earlier than the first signup, so a long period doesn't draw empty
    // months before launch. At least 7 days. Without a chosen bucket: daily up to 62 days, weekly
    // up to a year, then monthly.
    const range = adminDashboardRangeRowSchema.parse((await database`
        with first as (
            select least(${today}::date - 6, greatest(${today}::date - ${days - 1}::int,
                coalesce(min((created_at at time zone 'Europe/Paris')::date), '-infinity'::date))) as day
            from public.profiles
        )
        select date_trunc(bucket, day::timestamp)::date::text as start, bucket
        from first cross join lateral (
            select coalesce(${bucket ?? null}::text, case when ${today}::date - day < 62 then 'day'
                when ${today}::date - day < 366 then 'week' else 'month' end) as bucket
        ) as sized
    `)[0]);
    const w: AdminDashboardWindow = { now, today, start: range.start, bucket: range.bucket };
    const { cards, charts } = definitions(database, w, section);
    const failure = (error: unknown) => `Query failed: ${error instanceof Error ? error.message : String(error)}`;
    // NOTE: tiles take turns on the pool's connections, so each note's time is the tile's own
    // query, not its wait for a free connection.
    let free = database.options.max;
    const turns: (() => void)[] = [];
    const timed = async <T extends { note: string | null }>(tile: () => Promise<T>): Promise<T> => {
        if (free > 0) free--;
        else await new Promise<void>((resolve) => turns.push(resolve));
        const started = performance.now();
        try {
            const result = await tile();
            const took = `Took ${Math.floor((performance.now() - started) / 100) / 10} s.`;
            return { ...result, note: result.note ? `${result.note} ${took}` : took };
        } finally {
            const next = turns.shift();
            if (next) next();
            else free++;
        }
    };
    const [cardTiles, chartTiles] = await Promise.all([
        Promise.all(cards.map((card) => timed(async (): Promise<AdminDashboardCard> => {
            const tile = { id: card.id, title: card.title, unit: card.unit, higher_is_better: card.better };
            try {
                const row = adminDashboardCardRowSchema.parse((await card.query)[0]);
                return { ...tile, ...row, note: card.note ?? null };
            } catch (error) {
                return { ...tile, value: null, previous: null, note: failure(error) };
            }
        }))),
        Promise.all(charts.map((chart) => timed(async (): Promise<AdminDashboardChart> => {
            const tile = {
                id: chart.id, title: chart.title, kind: chart.kind, unit: chart.unit, x_kind: chart.x,
                definition: chart.definition,
            };
            try {
                const rows = await chart.query;
                const series = new Map<string, AdminDashboardChart["series"][number]>();
                const cells = chart.kind === "heatmap" ? rows.map((row) => adminDashboardCellRowSchema.parse(row)) : [];
                for (const raw of chart.kind === "heatmap" ? [] : rows) {
                    const row = adminDashboardChartRowSchema.parse(raw);
                    const name = row.series ?? chart.title;
                    const line = series.get(name) ?? { name, previous: false, points: [] };
                    line.points.push({ x: row.x, y: row.y });
                    series.set(name, line);
                }
                const built = { ...tile, note: chart.note ?? null, example: null, series: [...series.values()], cells };
                return { ...built, example: chart.example?.(exampleReader(built, w)) ?? null };
            } catch (error) {
                return { ...tile, note: failure(error), example: null, series: [], cells: [] };
            }
        }))),
    ]);
    return adminDashboardSchema.parse({
        section,
        days,
        environment,
        bucket: w.bucket,
        generated_at: now.toISOString(),
        sections: adminDashboardSectionValues.map((id) => ({ id, title: id[0].toUpperCase() + id.slice(1) })),
        cards: cardTiles,
        charts: chartTiles,
    });
}
