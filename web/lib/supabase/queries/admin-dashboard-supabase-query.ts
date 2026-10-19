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
    type AdminDashboardUnit,
    type AdminDashboardWindow,
} from "@/lib/types/admin/admin-dashboard";
import { adminUsersCountRowSchema, adminUsersSchema, type AdminUsers } from "@/lib/types/admin/admin-users";

/**
 * The last `span` days, rolling to now, against the `span` days before them; rows expose `at`.
 * A previous period that starts before the Paris day `from` stays empty.
 */
function eventCard(
    sql: Sql,
    w: AdminDashboardWindow,
    span: number,
    events: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
    from: AdminDashboardQueryFragment = sql`'-infinity'::date`,
): AdminDashboardQueryFragment {
    const start = new Date(w.now.getTime() - span * 86_400_000);
    const previousStart = new Date(w.now.getTime() - 2 * span * 86_400_000);
    return sql`
        select ${measure} filter (where e.at >= ${start} and e.at < ${w.now}) as value,
            case when ${previousStart} >= ${from}::timestamp at time zone 'Europe/Paris'
                then ${measure} filter (where e.at >= ${previousStart} and e.at < ${start}) end as previous
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
 * order, so a series keeps its place and colour whatever the period. Buckets that start before the
 * Paris day `from` are left out.
 */
function perBucket(
    sql: Sql,
    w: AdminDashboardWindow,
    rows: AdminDashboardQueryFragment,
    measure: AdminDashboardQueryFragment,
    { complete = false, gaps = false, series, from = sql`'-infinity'::date` }: {
        complete?: boolean; gaps?: boolean; series?: string[]; from?: AdminDashboardQueryFragment;
    } = {},
): AdminDashboardQueryFragment {
    const lastDay = complete ? sql`(${w.today}::date - 1)` : sql`${w.today}::date`;
    const day = complete ? sql`e.day` : sql`(e.at at time zone 'Europe/Paris')::date`;
    return sql`
        with buckets as (
            select bucket::date as bucket
            from generate_series(${w.start}::timestamp, date_trunc(${w.bucket}::text, ${lastDay}::timestamp),
                ('1 ' || ${w.bucket}::text)::interval) as bucket
            where bucket >= ${from}
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

/** "8,234", "42%", "1 day", "1.2 seconds": a number in an example sentence, in English. */
function readable(value: number, unit: AdminDashboardUnit): string {
    const digits = value.toLocaleString("en-US", { maximumFractionDigits: unit === "steps" ? 0 : 1 });
    if (unit === "percent") return `${digits}%`;
    if (unit === "count" || unit === "steps") return digits;
    return `${digits} ${digits === "1" ? unit.slice(0, -1) : unit}`;
}

/** "1 person", "6 people". */
function counted(value: number, one: string, many: string): string {
    const digits = readable(value, "count");
    return `${digits} ${digits === "1" ? one : many}`;
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
    const format = (value: number, unit = chart.unit) => readable(value, unit);
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
        count: counted,
        share,
        day,
        period,
    };
}

/**
 * Who counts as connected to Apple Health, referred, in a Fight, or a friend. The dashboard's tiles
 * and the Users table share these rules, so a person reads the same in both.
 */
function peopleRules(sql: Sql) {
    // NOTE: iOS answers a denied Apple Health read with an empty success, so a person counts as
    // connected only once their phone has sent a day with steps.
    const stepPeople = sql`
        select metric.user_id from private.activity_metrics as metric
        join public.data_sources as source on source.id = metric.source_id
        where metric.scope = 'day' and metric.metric = 'steps' and metric.value > 0 and source.provider = 'apple_health'
        union
        select legacy.user_id from public.metric_days as legacy
        join public.data_sources as source on source.id = legacy.source_id
        where legacy.metric = 'steps' and legacy.value > 0 and source.provider = 'apple_health'
    `;
    // Same 7-day rule as claimReferral: an older account that opens a share link to join a Fight is
    // not a referral. Rows from before that rule are kept, so the dashboard applies it. Dated by signup.
    const referrals = sql`
        select r.referrer_user_id as user_id, r.referred_user_id, referred.created_at as at
        from private.referrals as r
        join public.profiles as referred on referred.user_id = r.referred_user_id
        where referred.deleted_at is null and r.created_at <= referred.created_at + interval '7 days'
    `;
    // NOTE: the Production view runs this code on the preview server against production, which has no
    // host_id or friends column until 20261014140000_founder_fights and 20261015210000_friend_fights
    // reach it. to_jsonb(row) ->> 'column' reads null there and the column elsewhere; use the columns
    // directly once production has the migrations.
    // The app-wide and suggested Fights invite people automatically, and every friendship gets a
    // friend Fight; they distort social metrics.
    // A founder Fight counts for its challenger, who accepted a real 30-day Fight, but not for the
    // founder, who is in every one: tiles about a person's own progress add
    // `m.user_id::text is distinct from f.host`.
    const userFights = sql`
        select f.*, to_jsonb(f) ->> 'host_id' as host from public.fights as f
        left join public.fight_series as series on series.id = f.series_id
        where coalesce(series.join_code, '') <> 'PGG7' and not coalesce(series.suggested, false)
            and (to_jsonb(f) ->> 'friends') is distinct from 'true'
    `;
    // A Fight counts once someone besides its owner has accepted a round of it. A Fight nobody
    // joined, such as a solo test, is not a contest.
    const userContests = sql`
        select f.* from (${userFights}) as f
        where f.state not in ('draft', 'cancelled') and exists (
            select 1 from public.fights as round
            join public.fight_members as m on m.fight_id = round.id
            where round.series_id = f.series_id and m.state = 'accepted' and m.user_id <> round.owner_id
        )
    `;
    // NOTE: declining or removing a friend deletes the pair's row, so requests only count the
    // rows still here: pending or accepted. Deleted accounts and blocked pairs are left out,
    // like the app's friends list.
    const friendPairs = sql`
        select friendship.user_low, friendship.user_high, friendship.state, friendship.created_at,
            friendship.accepted_at
        from private.profile_friendships as friendship
        join public.profiles as low on low.user_id = friendship.user_low and low.deleted_at is null
        join public.profiles as high on high.user_id = friendship.user_high and high.deleted_at is null
        where not exists (
            select 1 from (
                select blocker_id, blocked_id from private.profile_blocks
                union all select blocker_id, blocked_id from private.feed_blocks
                union all select blocker_id, blocked_id from private.feedback_blocks
            ) as block
            where (block.blocker_id = friendship.user_low and block.blocked_id = friendship.user_high)
                or (block.blocker_id = friendship.user_high and block.blocked_id = friendship.user_low)
        )
    `;
    return { stepPeople, referrals, userFights, userContests, friendPairs };
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
    const { stepPeople, referrals, userFights, userContests } = peopleRules(sql);
    // NOTE: an open (or a pull to refresh) is a "foreground" (or "manual") trace that reads Apple
    // Health, or only refreshes Fights for someone without it. Not opens: that Fights refresh within
    // a minute after a background sync, the activity import after any sync (activity stages only),
    // and background relaunches that builds without the launch guard in FitFightApp record as opens:
    // on a locked phone (HealthKit error 6), or 59.5 to 66 minutes after the person's previous Health
    // sync, the beat of background delivery, which iOS can deliver late but not early. Ceiling, week
    // to 15 Oct: drops about 550 relaunches and about 25 real opens, and still counts about 150
    // relaunches that land later. Delete the hour rule once no installed build lacks the launch guard
    // (1.1.2 (210) and 1.1.3 (226) today); keep the error 6 rule, since nobody opens a locked phone.
    const activitySince = (floor: AdminDashboardQueryFragment) => sql`
        select traced.user_id, traced.started_at as at, traced.trigger, traced.app_version, traced.app_build
        from (
            select a.user_id, a.started_at, a.trigger, a.app_version, a.app_build, a.stages, a.health,
                max(a.started_at) filter (where a.trigger = 'observer')
                    over (partition by a.user_id order by a.started_at) as last_observer,
                max(a.started_at) filter (where a.trigger = 'observer' or a.health) over (
                    partition by a.user_id order by a.started_at rows between unbounded preceding and 1 preceding
                ) as last_health
            from (
                select attempt.*, attempt.trigger <> 'observer' and attempt.stages @? '$[*] ? (@.stage != "session" && @.stage != "fights_refresh" && @.stage != "healthkit_activity" && @.stage != "activity_upload")' as health
                from private.healthkit_sync_attempts as attempt
                where attempt.started_at >= ${floor}
            ) as a
        ) as traced
        where traced.trigger in ('foreground', 'manual')
            and (traced.health or (traced.stages @? '$[*] ? (@.stage == "session" || @.stage == "fights_refresh")'
                and (traced.last_observer is null or traced.started_at - traced.last_observer > interval '60 seconds')))
            and not traced.stages @> '[{"stage": "today_total", "error": {"kind": "healthkit", "code": 6}}]'
            and (traced.health and traced.trigger = 'foreground' and traced.started_at - traced.last_health
                between interval '59 minutes 30 seconds' and interval '66 minutes') is not true
    `;
    // NOTE: until 1 Oct 2026 servers deleted Health sync reports past 7 days or 100 per person,
    // keeping the last reports of people who left. App opens are complete from 2 Oct 2026, so
    // comparisons and chart buckets that start earlier stay empty.
    const openedFrom = sql`'2026-10-02'::date`;
    const kept = "App opens are complete from 2 Oct 2026";
    const background = "Background syncs are not opens. Older app builds also record some background relaunches by Apple Health as opens: those on a locked phone or 59.5 to 66 minutes after the last sync are left out, but some that land later still count, so opens read slightly high until people update.";
    // The month before the chart start feeds its monthly actives; 61 days feed the monthly cards.
    const activity = activitySince(
        sql`least(${w.start}::date - 31, ${w.today}::date - 61)::timestamp at time zone 'Europe/Paris'`,
    );
    const opens = sql`select * from (${activity}) as activity where activity.trigger = 'foreground'`;
    const activeDays = sql`
        select distinct user_id, (at at time zone 'Europe/Paris')::date as day from (${activity}) as activity
    `;
    // Complete Apple Health days only: a complete row beats a newer incomplete one (profile statistics
    // take the newest row), and real rows beat the Fight fallback.
    // Window-bound queries pass a floor so they do not sort years of imported history.
    // NOTE: 1.1.2 (210) phones that connected Health before 16 Sep 2026 fail their daily-Steps
    // upload (HealthKit error 5) but still upload Fight totals. A day without a complete daily row
    // takes the steps between two daily checkpoints of a Fight upload: whole days, highest Fight.
    // Remove once no installed build is 1.1.2 (210); silly and samuel upload no Fights and stay missing.
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
                union all
                select fight.user_id, fight.day, max(fight.steps), max(fight.updated_at), true, -1
                from (
                    select snapshot.user_id, snapshot.created_at as updated_at, (point.value->>'day')::date as day,
                        (point.value->>'steps')::float8 - coalesce(lag((point.value->>'steps')::float8)
                            over (partition by snapshot.id order by point.ordinality), 0) as steps,
                        (point.value->>'cutoff_at')::timestamptz = ((point.value->>'day')::date + 1)::timestamp at time zone f.time_zone
                            and (point.value->>'day')::date::timestamp at time zone f.time_zone >= f.starts_at as whole
                    from (
                        select distinct on (s.fight_id, s.user_id) s.id, s.fight_id, s.user_id, s.created_at, s.step_checkpoints
                        from private.fight_score_snapshots as s
                        where s.step_checkpoints is not null and s.cutoff_at >= ${floor}
                        order by s.fight_id, s.user_id, s.cutoff_at desc, s.created_at desc
                    ) as snapshot
                    join public.fights as f on f.id = snapshot.fight_id
                    cross join lateral jsonb_array_elements(snapshot.step_checkpoints) with ordinality as point
                ) as fight
                where fight.whole and fight.day >= ${floor}
                group by fight.user_id, fight.day
            ) as days
            order by days.user_id, days.day, days.finalized desc, days.priority < 0, days.updated_at desc, days.priority desc
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
    // Fight counts and social tiles leave founder Fights out entirely.
    const realFights = sql`select * from (${userFights}) as f where f.host is null`;
    const fightDays = sql`
        select s.*, exists (
            select 1 from public.fight_members as m
            join (${userFights}) as f on f.id = m.fight_id
            where m.user_id = s.user_id and m.state = 'accepted' and f.state not in ('draft', 'cancelled')
                and m.user_id::text is distinct from f.host
                and m.accepted_at < (s.day + 1)::timestamp at time zone f.time_zone
                and f.starts_at < (s.day + 1)::timestamp at time zone f.time_zone
                and f.ends_at > s.day::timestamp at time zone f.time_zone
                and exists (
                    select 1 from public.fight_members as rival
                    where rival.fight_id = f.id and rival.state = 'accepted' and rival.user_id <> m.user_id
                )
        ) as in_fight
        from (${recentSteps}) as s
    `;
    const contests = sql`select * from (${userContests}) as f where f.host is null`;
    // Rounds with one accepted fighter are not contests either.
    const rounds = sql`
        select f.* from public.fights as f
        where (to_jsonb(f) ->> 'host_id') is null and (to_jsonb(f) ->> 'friends') is distinct from 'true' and (
            select count(*) from public.fight_members as m where m.fight_id = f.id and m.state = 'accepted'
        ) > 1
    `;
    const firstRounds = sql`
        select f.id, f.series_id, f.owner_id as user_id, f.created_at as at from (${contests}) as f
        where not exists (
            select 1 from public.fights as earlier
            where earlier.series_id = f.series_id and earlier.starts_at < f.starts_at
        )
    `;
    // A new round of a repeating Fight copies its roster; only a person's first round of a Fight is a join.
    const joins = sql`
        select m.user_id, m.accepted_at as at from public.fight_members as m
        join (${realFights}) as f on f.id = m.fight_id
        where m.state = 'accepted' and m.accepted_at is not null and m.user_id <> f.owner_id
            and not exists (
                select 1 from public.fight_members as earlier
                join public.fights as round on round.id = earlier.fight_id
                where round.series_id = f.series_id and round.starts_at < f.starts_at
                    and earlier.user_id = m.user_id and earlier.state = 'accepted'
            )
    `;
    const totalUsers: AdminDashboardCardDefinition = {
        id: "total_users", title: "Total users", unit: "count", better: true,
        note: "Now, vs 7 days ago. Deleted accounts are not counted.",
        definition: "Everyone with a FitFight account now, compared with 7 days ago. Deleted accounts are not counted. It counts accounts, so a person with two accounts counts twice.",
        example: (r) => `FitFight has ${r.count(r.value, "user", "users")} now${r.against("a week ago")}.`,
        query: sql`
            select count(*)::float8 as value, count(*) filter (where created_at < ${ago(7)})::float8 as previous
            from public.profiles where deleted_at is null
        `,
    };
    const weeklyNewUsers: AdminDashboardCardDefinition = {
        id: "new_users", title: "Weekly new users", unit: "count", better: true,
        note: "Last 7 days vs the 7 before.",
        definition: "Accounts created in the last 7 days, up to now, compared with the 7 days before. Deleted accounts are not counted.",
        example: (r) => `${r.count(r.value, "person", "people")} signed up in the last 7 days${r.against("in the 7 days before")}.`,
        query: eventCard(sql, w, 7, profiles, count),
    };
    const weeklyActive: AdminDashboardCardDefinition = {
        id: "weekly_active", title: "Weekly active users", unit: "count", better: true,
        note: "Opened the app in the last 7 days, vs the 7 before. Older builds read slightly high.",
        definition: `People who opened the app at least once in the last 7 days, up to now, compared with the 7 days before. Each person counts once. ${background} ${kept}, so the comparison shows from 16 Oct.`,
        example: (r) => `${r.count(r.value, "person", "people")} opened the app in the last 7 days${r.against("in the 7 days before")}.`,
        query: eventCard(sql, w, 7, activity, people, openedFrom),
    };
    const monthlyActive: AdminDashboardCardDefinition = {
        id: "monthly_active", title: "Monthly active users", unit: "count", better: true,
        note: "Opened the app in the last 30 days, vs the 30 before.",
        definition: `People who opened the app at least once in the last 30 days, up to now, compared with the 30 days before. Each person counts once. ${background} ${kept}, so the comparison shows from 1 Dec.`,
        example: (r) => `${r.count(r.value, "person", "people")} opened the app in the last 30 days${r.against("in the 30 days before")}.`,
        query: eventCard(sql, w, 30, activity, people, openedFrom),
    };
    const weeklyOpens: AdminDashboardCardDefinition = {
        id: "app_opens", title: "Weekly app opens", unit: "count", better: true,
        note: "Last 7 days vs the 7 before. Older builds read slightly high.",
        definition: `How many times people opened the app in the last 7 days, up to now, compared with the 7 days before. Each launch or return to the app counts. A pull to refresh is not an open, and neither are the syncs that follow an open or a background sync. ${background} ${kept}, so the comparison shows from 16 Oct.`,
        example: (r) => `The app was opened ${r.count(r.value, "time", "times")} in the last 7 days${r.against("in the 7 days before")}.`,
        query: eventCard(sql, w, 7, opens, count, openedFrom),
    };
    const liveFights: AdminDashboardCardDefinition = {
        id: "live_fights", title: "Live fights", unit: "count", better: true,
        note: "Now, vs 7 days ago. App-wide Fight included, founder and friend Fights and solo rounds not.",
        definition: "Fights running now with two or more fighters, compared with 7 days ago. The app-wide Fight counts. Drafts, cancelled Fights, founder Fights, friend Fights and rounds with one fighter do not.",
        example: (r) => `${r.count(r.value, "fight is", "fights are")} live now${r.against("a week ago")}.`,
        query: sql`
            select count(*) filter (where starts_at <= ${w.now} and ends_at > ${w.now})::float8 as value,
                count(*) filter (where starts_at <= ${ago(7)} and ends_at > ${ago(7)})::float8 as previous
            from (${rounds}) as f where f.state not in ('draft', 'cancelled')
        `,
    };
    const weeklyFightsCreated: AdminDashboardCardDefinition = {
        id: "fights_started", title: "Weekly fights created", unit: "count", better: true,
        note: "New Fights someone else joined, not later rounds, app-wide, founder or friend ones. Last 7 days vs the 7 before.",
        definition: "New Fights created in the last 7 days, up to now, compared with the 7 days before. A Fight counts once someone besides its owner joins it, so recent days can still grow. Later rounds of a repeating Fight, cancelled Fights, the app-wide Fight, suggested Fights, founder Fights and friend Fights are not counted.",
        example: (r) => `${r.count(r.value, "new fight was", "new fights were")} created in the last 7 days${r.against("in the 7 days before")}.`,
        query: eventCard(sql, w, 7, firstRounds, count),
    };
    const weeklySteps: AdminDashboardCardDefinition = {
        id: "steps_walked", title: "Weekly steps", unit: "steps", better: true,
        note: "The 7 complete days before today, vs the 7 before. New signups add to it.",
        definition: "Steps from Apple Health over the 7 complete days before today, added up for everyone, compared with the 7 days before. Only complete days, from each person's signup day, so people who joined this week raise it too. A phone adds yesterday at its next sync, so the newest day can still grow. A day a phone sent only inside a Fight upload counts from that Fight's daily checkpoints.",
        example: (r) => `FitFight people walked ${r.format(r.value)} steps in the last 7 complete days${r.against("in the 7 days before")}.`,
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
        definition: `How many times people opened the app in each ${w.bucket}. Each launch or return to the app counts. A pull to refresh is not an open, and neither are the syncs that follow an open or a background sync. ${background} ${kept}; earlier ${w.bucket}s are left out.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `The app was opened ${r.count(n, "time", "times")} ${r.when}.`;
        },
        note: `${kept}; earlier ${w.bucket}s are left out.`,
        query: perBucket(sql, w, opens, count, { gaps: true, from: openedFrom }),
    };
    const fightsCreatedChart: AdminDashboardChartDefinition = {
        id: "fights_created_per_bucket", title: `Fights created ${per}`, kind: "bar", unit: "count", x: "date",
        definition: `New Fights created in each ${w.bucket}. A Fight counts once someone besides its owner joins it, so recent ${w.bucket}s can still grow. Later rounds of a repeating Fight, cancelled Fights, the app-wide Fight, suggested Fights, founder Fights and friend Fights are not counted.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `${r.count(n, "new fight was", "new fights were")} created ${r.when}.`;
        },
        note: "New Fights someone else joined, not later rounds. App-wide, suggested, founder and friend Fights excluded.",
        query: perBucket(sql, w, firstRounds, count),
    };
    const stepsChart: AdminDashboardChartDefinition = {
        id: "steps_per_bucket", title: `Steps ${per}`, kind: "bar", unit: "steps", x: "date",
        definition: `Steps from Apple Health in each ${w.bucket}, added up for everyone. Only complete days, from each person's signup day. A day a phone sent only inside a Fight upload counts from that Fight's daily checkpoints.`,
        example: (r) => {
            const n = r.at();
            return n === undefined ? null : `FitFight people walked ${r.format(n)} steps ${r.when}.`;
        },
        note: "Complete days since each person joined, through yesterday, which still grows as phones sync.",
        query: perBucket(sql, w, recentSteps, sql`sum(e.steps)`, { complete: true }),
    };

    switch (section) {
        case "overview":
            return {
                cards: [
                    totalUsers, weeklyActive, monthlyActive, weeklyNewUsers, weeklyFightsCreated, liveFights,
                    weeklySteps,
                    {
                        id: "health_connected", title: "Weekly people syncing Health", unit: "count", better: true,
                        note: "Phone synced Apple Health in the last 7 days, vs the 7 before.",
                        definition: "People whose phone synced Apple Health at least once in the last 7 days, up to now, compared with the 7 days before. iOS does not tell FitFight when someone turns Health off or deletes the app, so a phone that stops syncing is how a lost connection shows.",
                        example: (r) => `${r.count(r.value, "person's phone", "people's phones")} synced Apple Health in the last 7 days${r.against("in the 7 days before")}.`,
                        query: sql`
                            select count(distinct user_id) filter (where started_at >= ${ago(7)})::float8 as value,
                                count(distinct user_id) filter (where started_at < ${ago(7)})::float8 as previous
                            from private.healthkit_sync_attempts
                            where outcome = 'succeeded' and started_at >= ${ago(14)} and started_at < ${w.now}
                                and (stages @> '[{"stage":"today_total"}]' or stages @> '[{"stage":"local_state"}]')
                        `,
                    },
                ],
                charts: [
                    totalUsersChart, newUsersChart,
                    {
                        id: "active_users_per_bucket", title: `Active users ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `People who opened the app at least once in each ${w.bucket}. Each person counts once per ${w.bucket}. ${background} ${kept}; earlier ${w.bucket}s are left out.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} opened the app ${r.when}.`;
                        },
                        note: `Distinct people who opened the app in each ${w.bucket}. ${kept}; earlier ${w.bucket}s are left out.`,
                        query: perBucket(sql, w, activity, people, { gaps: true, from: openedFrom }),
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
                        definition: "Accounts created in the last 30 days, up to now, compared with the 30 days before. Deleted accounts are not counted.",
                        example: (r) => `${r.count(r.value, "person", "people")} signed up in the last 30 days${r.against("in the 30 days before")}.`,
                        query: eventCard(sql, w, 30, profiles, count),
                    },
                    ...[
                        {
                            id: "onboarding_rate", title: "Monthly username rate", did: "picked a username",
                            definition: "Of the people who signed up in the last 30 days, the share who have picked a username, compared with the people who signed up in the 30 days before. Recent signups have had less time to do it.",
                            condition: sql`p.handle_set_at is not null`,
                        },
                        {
                            id: "health_rate", title: "Monthly Health connect rate", did: "connected Apple Health",
                            definition: "Of the people who signed up in the last 30 days, the share who have connected Apple Health, compared with the people who signed up in the 30 days before. Connected means their phone has sent at least one day with steps; allowing Health without read access sends none. A connection turned off later still counts. Recent signups have had less time to do it.",
                            condition: sql`p.user_id in (${stepPeople})`,
                        },
                        {
                            id: "fight_rate", title: "Monthly fight join rate", did: "joined a fight",
                            definition: "Of the people who signed up in the last 30 days, the share who have joined a fight, compared with the people who signed up in the 30 days before. Creating a fight counts once someone else joins it. Cancelled Fights, the app-wide Fight and suggested Fights do not. Founder Fights count for the challenger only, and friend Fights do not count. Recent signups have had less time to do it.",
                            condition: sql`exists (
                                select 1 from public.fight_members as m join (${userContests}) as f on f.id = m.fight_id
                                where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host)`,
                        },
                        {
                            id: "referral_rate", title: "Monthly referral rate", did: "came from a referral",
                            definition: "Of the people who signed up in the last 30 days, the share who came through someone's referral link, compared with the people who signed up in the 30 days before. A referral counts only when claimed within 7 days of signing up.",
                            condition: sql`p.user_id in (select r.referred_user_id from (${referrals}) as r)`,
                        },
                    ].map(({ id, title, did, definition, condition }): AdminDashboardCardDefinition => ({
                        id, title, unit: "percent", better: true,
                        note: `Share of the last 30 days' signups who ${did}, vs the 30 days before.`,
                        definition,
                        example: (r) => `${r.format(r.value)} of the people who signed up in the last 30 days ${did}${r.against("for the 30 days before")}.`,
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
                        id: "days_to_first_fight", title: "Monthly time to first fight", unit: "minutes", better: false,
                        note: "Median, for the last 30 days' signups who joined a fight, vs the 30 days before.",
                        definition: "The median time from signup to joining a first fight, in minutes, for the people who signed up in the last 30 days and have joined one, compared with the people who signed up in the 30 days before. Half of them joined faster. Creating a fight counts once someone else joins it. Cancelled Fights, the app-wide Fight and suggested Fights do not. Founder Fights count for the challenger only, and friend Fights do not count.",
                        example: (r) => `Half of the people who signed up in the last 30 days and joined a fight did it within ${r.format(r.value)}${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select * from (
                                select p.user_id, p.created_at as at, extract(epoch from (
                                    select min(m.accepted_at) from public.fight_members as m
                                    join (${userContests}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host
                                ) - p.created_at) / 60 as waited
                                from public.profiles as p where p.deleted_at is null
                            ) as waits where waits.waited is not null
                        `, sql`percentile_cont(0.5) within group (order by greatest(e.waited, 0))`),
                    },
                    {
                        id: "referrals", title: "Monthly referrals", unit: "count", better: true,
                        note: "Last 30 days vs the 30 before.",
                        definition: "Signups in the last 30 days, up to now, that came through someone's referral link, compared with the 30 days before. A referral counts only when claimed within 7 days of signing up, so an older account opening a link to join a fight does not count.",
                        example: (r) => `${r.count(r.value, "person", "people")} joined through a referral in the last 30 days${r.against("in the 30 days before")}.`,
                        query: eventCard(sql, w, 30, referrals, count),
                    },
                    {
                        id: "monthly_referrers", title: "Monthly referrers", unit: "count", better: true,
                        note: "People whose link brought a signup in the last 30 days, vs the 30 before.",
                        definition: "People whose referral link brought at least one signup in the last 30 days, up to now, compared with the 30 days before. Each person counts once, however many people they brought. A referral counts only when claimed within 7 days of signing up.",
                        example: (r) => `${r.count(r.value, "person's link", "people's links")} brought someone to FitFight in the last 30 days${r.against("in the 30 days before")}.`,
                        query: eventCard(sql, w, 30, referrals, people),
                    },
                    {
                        id: "referrer_share", title: "Users who referred someone", unit: "percent", better: true,
                        note: "Share of all users whose link brought a signup, now vs 7 days ago.",
                        definition: "The share of all users whose referral link has brought at least one signup, now, compared with 7 days ago. A referral counts only when claimed within 7 days of signing up. Deleted accounts are not counted.",
                        example: (r) => `${r.format(r.value)} of users have brought someone to FitFight${r.against("a week ago")}.`,
                        query: sql`
                            select 100.0 * count(*) filter (where p.user_id in (select r.user_id from (${referrals}) as r))
                                    / nullif(count(*), 0) as value,
                                100.0 * count(*) filter (where p.created_at < ${ago(7)} and p.user_id in (
                                        select r.user_id from (${referrals}) as r where r.at < ${ago(7)}))
                                    / nullif(count(*) filter (where p.created_at < ${ago(7)}), 0) as previous
                            from public.profiles as p
                            where p.deleted_at is null
                        `,
                    },
                ],
                charts: [
                    ...[
                        { id: "user_growth_wow", title: "Week-over-week user growth", span: 7, name: "week" },
                        { id: "user_growth_mom", title: "Month-over-month user growth", span: 30, name: "month" },
                    ].map(({ id, title, span, name }): AdminDashboardChartDefinition => ({
                        id, title, kind: "line", unit: "percent", x: "date",
                        definition: `How much the number of users grew in the ${span} days up to the end of each ${w.bucket}: total users then against total users ${span} days earlier. A point shows only once there were at least 20 users ${span} days earlier, so a tiny early base does not draw huge percentages.`,
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
                            having count(*) filter (where p.joined_day <= point.day - ${span}::int) >= 20
                            order by point.bucket
                        `,
                    })),
                    newUsersChart, totalUsersChart,
                    {
                        id: "onboarding_by_signup", title: `Onboarding by signup ${w.bucket}`, kind: "line", unit: "percent", x: "date",
                        definition: `For the people who signed up in each ${w.bucket}: the share who picked a username, connected Apple Health and joined a fight, as of now. Connected Apple Health means their phone has sent at least one day with steps. Creating a fight counts once someone else joins it. Cancelled, app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count. A ${w.bucket} with fewer than 5 signups is left out, because one person would swing it. Recent signups have had less time, so their shares can still grow.`,
                        example: (r) => {
                            const name = r.at("Picked a username");
                            const health = r.at("Connected Apple Health");
                            const fight = r.at("Joined a fight");
                            if (name === undefined || health === undefined || fight === undefined) return null;
                            return `Of the people who signed up ${r.when}, ${r.format(name)} picked a username, ${r.format(health)} connected Apple Health and ${r.format(fight)} joined a fight.`;
                        },
                        note: `Share of each ${w.bucket}'s signups who did each step, as of now. Only ${w.bucket}s with 5 or more signups. Recent signups have had less time.`,
                        query: perBucket(sql, w, sql`
                            select p.at, step.series, step.done
                            from (${profiles}) as p
                            cross join lateral (values
                                ('Picked a username', p.handle_set_at is not null),
                                ('Connected Apple Health', p.user_id in (${stepPeople})),
                                ('Joined a fight', exists (
                                    select 1 from public.fight_members as m join (${userContests}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host))
                            ) as step(series, done)
                        `, sql`case when count(*) >= 5 then avg(case when e.done then 100.0 else 0 end) end`, {
                            gaps: true, series: ["Picked a username", "Connected Apple Health", "Joined a fight"],
                        }),
                    },
                    {
                        id: "referrals_per_bucket", title: `Referrals ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Signups that came through someone's referral link, in each ${w.bucket} of signup. A referral counts only when claimed within 7 days of signing up.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "person", "people")} joined through a referral ${r.when}.`;
                        },
                        query: perBucket(sql, w, referrals, count),
                    },
                    ...[
                        { id: "funnel_period", title: "Onboarding funnel, last 30 days' signups", who: "the people who signed up in the last 30 days", scope: sql`p.created_at >= ${ago(30)}` },
                        { id: "funnel_all", title: "Onboarding funnel, all users", who: "all users", scope: sql`true` },
                    ].map(({ id, title, who, scope }): AdminDashboardChartDefinition => ({
                        id, title, kind: "bar", unit: "count", x: "label",
                        definition: `How far ${who} got: picking a username, connecting Apple Health, joining a first fight, finishing one and joining a second. Connecting Apple Health means their phone has sent at least one day with steps. A repeating Fight counts once, and creating a fight counts once someone else joins it. Cancelled, app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count.`,
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
                                    p.user_id in (${stepPeople}) as health,
                                    (select count(distinct f.series_id) from public.fight_members as m
                                        join (${userContests}) as f on f.id = m.fight_id
                                        where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host) as fights,
                                    exists (select 1 from public.fight_members as m
                                        join (${userContests}) as f on f.id = m.fight_id
                                        where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host
                                            and f.state = 'final') as finished
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
                        definition: "Each person's saved time zone, a rough guide to where they live. People without a saved time zone are left out: most accounts created before 28 Sep 2026 have none.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.share} of users with a saved time zone are in ${r.top.x} (${r.format(r.top.y)}).` : null),
                        query: sql`
                            select time_zone as x, count(*)::float8 as y
                            from public.profiles where deleted_at is null and time_zone is not null group by 1 order by 2 desc, 1 limit 12
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
                        definition: "People whose referral links brought the most signups, all time. A referral counts only when claimed within 7 days of signing up.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} brought ${r.count(r.top.y, "person", "people")} to FitFight.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(*)::float8 as y
                            from (${referrals}) as r join public.profiles as p on p.user_id = r.user_id
                            group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "referred_vs_others", title: "Onboarding by referral, all users", kind: "table", unit: "percent", x: "label",
                        definition: "All users in two groups: those who came through someone's referral link and the others. Each row is the share of the group who did that step, as of now. A referral counts only when claimed within 7 days of signing up. Connected Apple Health means their phone has sent at least one day with steps. Creating a fight counts once someone else joins it. Cancelled, app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count. A group with fewer than 5 people is left out, because one person would swing it.",
                        example: (r) => {
                            const fought = (group: string) => r.series.find((line) => line.name === group)
                                ?.points.find((point) => point.x === "Joined a fight")?.y;
                            const referred = fought("Referred");
                            const others = fought("Not referred");
                            return referred === undefined || others === undefined ? null
                                : `${r.format(referred)} of referred users joined a fight, against ${r.format(others)} of the others.`;
                        },
                        note: "Share of each group, as of now. Groups under 5 people are left out.",
                        query: sql`
                            with cohort as (
                                select p.user_id in (select r.referred_user_id from (${referrals}) as r) as referred,
                                    p.handle_set_at is not null as named,
                                    p.user_id in (${stepPeople}) as health,
                                    exists (select 1 from public.fight_members as m
                                        join (${userContests}) as f on f.id = m.fight_id
                                        where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host) as fought,
                                    p.user_id in (select r.user_id from (${referrals}) as r) as referring
                                from public.profiles as p
                                where p.deleted_at is null
                            )
                            select step.x, (100.0 * count(*) filter (where step.done) / count(*))::float8 as y,
                                case when cohort.referred then 'Referred' else 'Not referred' end as series
                            from cohort
                            cross join lateral (values
                                (1, 'Picked a username', cohort.named),
                                (2, 'Connected Apple Health', cohort.health),
                                (3, 'Joined a fight', cohort.fought),
                                (4, 'Referred someone', cohort.referring)
                            ) as step(position, x, done)
                            group by cohort.referred, step.position, step.x
                            having count(*) >= 5
                            order by cohort.referred desc, step.position
                        `,
                    },
                ],
            };
        case "retention": {
            // NOTE: retention follows people whose phone has sent Apple Health steps. Their phones sync steps
            // in the background, opened or not, until the app is deleted or Health is turned off.
            // App opens can't be used: they are complete only from 2 Oct 2026. The floor
            // covers the last 6 signup months, the cards' cohorts and the chart period.
            const synced = sql`
                select distinct history.user_id, history.day
                from (${stepHistory(sql`least(${w.start}::date, ${w.today}::date - 200)`)}) as history
                where history.day >= history.joined_day
            `;
            const withHealth = sql`
                select p.user_id, p.joined_day, p.at from (${profiles}) as p
                where p.user_id in (${stepPeople})
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
                select case when count(*) filter (where not e.previous) >= 10
                        then 100.0 * count(h.user_id) filter (where not e.previous) / count(*) filter (where not e.previous)
                    end as value,
                    case when count(*) filter (where e.previous) >= 10 and count(*) filter (where not e.previous) >= 10
                        then 100.0 * count(h.user_id) filter (where e.previous) / count(*) filter (where e.previous)
                    end as previous
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
                        definition: "People who signed up in the 30 complete days before today and connected Apple Health, compared with the 30 days before. Connected means their phone has sent at least one day with steps. These are the people retention follows.",
                        example: (r) => `${r.count(r.value, "person", "people")} signed up and connected Apple Health in the last 30 complete days${r.against("in the 30 days before")}.`,
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
                        definition: `The share of people with Apple Health whose phone synced steps for at least one day from day ${from} to day ${to} after signup. Day 0 is the signup day. It covers the latest ${span} days of signups that are past day ${to}, compared with the ${span} days of signups before them. A number shows only when its group has at least 10 people, and the comparison only when both groups do. A phone syncs in the background until the app is deleted or Health is turned off. A phone that comes back after a gap uploads the days it missed, and those days count.`,
                        example: (r) => `${r.format(r.value)} of the latest ${span} days' signups with Apple Health still synced steps from day ${from} to day ${to}${r.against(`for the ${span} days of signups before`)}.`,
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
                        definition: `For each signup ${cohort}: the share of people with Apple Health whose phone still synced steps in week 1 (days 7 to 13) and week 4 (days 28 to 34) after signing up. It shows if newer signups stay longer. Week 4 needs signups at least 35 days old, so it shows only on periods longer than 30 days. A ${cohort} with fewer than 5 people is left out.`,
                        example: (r) => {
                            const week = r.series.find((line) => line.name === "Week 1")?.points.at(-1);
                            return week
                                ? `Of the people who signed up in the ${cohort} starting ${r.day(week.x)}, ${r.format(week.y)} still synced steps in week 1.`
                                : null;
                        },
                        note: `Share of each signup ${cohort}'s people with Apple Health whose phone still synced steps in week 1 (days 7 to 13) and week 4 (days 28 to 34). People count once they get there. Week 4 needs a period over 30 days. Only ${cohort}s with 5 or more people.`,
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
                                having count(*) >= 5
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
        case "churn": {
            // NOTE: churn by app opens reads only periods from 2 Oct 2026 (see `openedFrom`); earlier
            // ones would read too high. Phone syncs (step days) were never deleted.
            const floor = sql`least(${w.start}::date - 60, ${w.today}::date - 90)`;
            const opened = sql`
                select distinct user_id, (at at time zone 'Europe/Paris')::date as day
                from (${activitySince(sql`${floor}::timestamp at time zone 'Europe/Paris'`)}) as activity
            `;
            const synced = sql`
                select distinct history.user_id, history.day from (${stepHistory(floor)}) as history
                where history.day >= history.joined_day
            `;
            // People active in the `span` complete days before the latest `span` who were not active
            // in the latest, as a share or a number, against the same `span` days earlier. A value
            // whose first day is before `from` stays empty.
            const churnCard = (days: AdminDashboardQueryFragment, span: number, share: boolean, from = sql`'-infinity'::date`) => {
                const measure = (shift: number) => sql`
                    case when ${w.today}::date - ${shift + 2 * span}::int >= ${from} then ${share
                        ? sql`100.0 * count(*) filter (where e.shift = ${shift}::int and not e.stayed)
                            / nullif(count(*) filter (where e.shift = ${shift}::int), 0)`
                        : sql`count(*) filter (where e.shift = ${shift}::int and not e.stayed)::float8`} end
                `;
                return sql`
                    select ${measure(0)} as value, ${measure(span)} as previous
                    from (
                        select a.user_id, k.shift,
                            bool_or(a.day < ${w.today}::date - k.shift - ${span}::int) as was,
                            bool_or(a.day >= ${w.today}::date - k.shift - ${span}::int) as stayed
                        from (${days}) as a
                        cross join (values (0), (${span}::int)) as k(shift)
                        where a.day >= ${w.today}::date - k.shift - ${2 * span}::int and a.day < ${w.today}::date - k.shift
                        group by a.user_id, k.shift
                    ) as e
                    where e.was
                `;
            };
            // The same weekly and monthly churn, read on the complete days up to the end of each
            // bucket. A bucket without a complete day yet is left out.
            const churnLines = (days: AdminDashboardQueryFragment, from = sql`'-infinity'::date`) => sql`
                with active as materialized (${days}),
                ends as (
                    select point.bucket, least(point.day, ${w.today}::date - 1) as day, span.series, span.position, span.days
                    from (${samplePoints(sql, w)}) as point
                    cross join (values ('Weekly churn', 1, 7), ('Monthly churn', 2, 30)) as span(series, position, days)
                    where point.bucket < ${w.today}::date
                        and least(point.day, ${w.today}::date - 1) - 2 * span.days + 1 >= ${from}
                ),
                flags as (
                    select ends.bucket, ends.series, ends.position, a.user_id,
                        bool_or(a.day <= ends.day - ends.days) as was, bool_or(a.day > ends.day - ends.days) as stayed
                    from ends join active as a on a.day > ends.day - 2 * ends.days and a.day <= ends.day
                    group by ends.bucket, ends.series, ends.position, a.user_id
                )
                select bucket::text as x, (100.0 * count(*) filter (where not stayed) / count(*))::float8 as y, series
                from flags where was
                group by bucket, series, position
                having count(*) >= 10
                order by position, bucket
            `;
            return {
                cards: [
                    ...[
                        { id: "weekly_churn", title: "Weekly churn", span: 7, share: true, starts: "16 Oct" },
                        { id: "monthly_churn", title: "Monthly churn", span: 30, share: true, starts: "1 Dec" },
                        { id: "weekly_churned", title: "Weekly churned users", span: 7, share: false, starts: "16 Oct" },
                        { id: "monthly_churned", title: "Monthly churned users", span: 30, share: false, starts: "1 Dec" },
                    ].map(({ id, title, span, share, starts }): AdminDashboardCardDefinition => {
                        const before = `${span + 1} to ${2 * span} days ago`;
                        const earlier = span === 7 ? "a week earlier" : "30 days earlier";
                        return {
                            id, title, unit: share ? "percent" : "count", better: false,
                            note: `${share ? "Share" : "People"} who opened the app ${before} but not in the last ${span} days, vs ${earlier}.`,
                            definition: `${share ? "The share" : "The number"} of people who opened the app ${before} and did not open it in the ${span} complete days before today, compared with ${earlier}. ${background} ${kept}, so it shows from ${starts}.`,
                            example: (r) => share
                                ? `${r.format(r.value)} of the people who opened the app ${before} did not open it in the last ${span} days${r.against(earlier)}.`
                                : `${r.count(r.value, "person", "people")} who opened the app ${before} did not open it in the last ${span} days${r.against(earlier)}.`,
                            query: churnCard(opened, span, share, openedFrom),
                        };
                    }),
                    ...[
                        { id: "weekly_sync_churn", title: "Weekly sync churn", span: 7 },
                        { id: "monthly_sync_churn", title: "Monthly sync churn", span: 30 },
                    ].map(({ id, title, span }): AdminDashboardCardDefinition => {
                        const before = `${span + 1} to ${2 * span} days ago`;
                        const earlier = span === 7 ? "a week earlier" : "30 days earlier";
                        return {
                            id, title, unit: "percent", better: false,
                            note: `Share whose phone synced steps ${before} but not in the last ${span} days, vs ${earlier}.`,
                            definition: `The share of people whose phone synced Apple Health steps ${before} and synced no day in the ${span} complete days before today, compared with ${earlier}. A phone syncs in the background until the app is deleted or Health is turned off, so these people left, not just stopped opening the app. A phone that comes back uploads the days it missed, so people who return no longer count.`,
                            example: (r) => `${r.format(r.value)} of the people whose phone synced steps ${before} synced none in the last ${span} days${r.against(earlier)}.`,
                            query: churnCard(synced, span, true),
                        };
                    }),
                ],
                charts: [
                    {
                        id: "churn_rate", title: "Weekly and monthly churn", kind: "line", unit: "percent", x: "date",
                        definition: `Weekly churn: of the people who opened the app in the 7 days before the last 7, the share who did not open it in the last 7. Monthly churn: the same with 30 days. Each point reads the complete days up to the end of its ${w.bucket}. ${kept}, so weekly points start on 15 Oct and monthly points on 30 Nov.`,
                        example: (r) => {
                            const weekly = r.at("Weekly churn");
                            const monthly = r.at("Monthly churn");
                            if (weekly === undefined) return null;
                            return `Weekly churn was ${r.format(weekly)} ${r.when}${monthly === undefined ? "" : `, and monthly churn ${r.format(monthly)}`}.`;
                        },
                        note: `Stopped opening the app. Complete days up to the end of each ${w.bucket}. ${kept}.`,
                        query: churnLines(opened, openedFrom),
                    },
                    {
                        id: "users_gained_lost", title: "Weekly users gained and lost", kind: "bar", unit: "count", x: "date",
                        definition: `People who opened the app in the 7 complete days up to the end of each ${w.bucket}, against the 7 days before. New: signed up in those 7 days. Came back: opened the app again after 7 days or more away. Stopped: opened it in the 7 days before, not in these 7, drawn below zero. ${kept}.`,
                        example: (r) => {
                            const fresh = r.at("New");
                            const back = r.at("Came back");
                            const lost = r.at("Stopped");
                            if (fresh === undefined || back === undefined || lost === undefined) return null;
                            const span = w.bucket === "day" ? "the 7 days up to then" : `the last 7 days of that ${w.bucket}`;
                            return `${r.when[0].toUpperCase()}${r.when.slice(1)}, ${r.count(fresh, "new person", "new people")} and ${r.count(back, "person who came back", "people who came back")} opened the app in ${span}, and ${r.count(-lost, "person", "people")} stopped.`;
                        },
                        note: `The 7 complete days up to the end of each ${w.bucket} against the 7 before. Stopped is below zero.`,
                        query: sql`
                            with active as materialized (${opened}),
                            ends as (
                                select point.bucket, least(point.day, ${w.today}::date - 1) as day
                                from (${samplePoints(sql, w)}) as point
                                where point.bucket < ${w.today}::date
                                    and least(point.day, ${w.today}::date - 1) - 13 >= ${openedFrom}
                            ),
                            flags as (
                                select ends.bucket, ends.day, a.user_id,
                                    bool_or(a.day > ends.day - 7) as opened, bool_or(a.day <= ends.day - 7) as was
                                from ends join active as a on a.day > ends.day - 14 and a.day <= ends.day
                                group by ends.bucket, ends.day, a.user_id
                            ),
                            counted as (
                                select f.bucket,
                                    count(*) filter (where f.opened and not f.was and p.joined_day > f.day - 7) as fresh,
                                    count(*) filter (where f.opened and not f.was and p.joined_day <= f.day - 7) as back,
                                    count(*) filter (where f.was and not f.opened) as lost
                                from flags as f join (${profiles}) as p using (user_id)
                                group by f.bucket
                            )
                            select counted.bucket::text as x, value.y::float8 as y, value.series
                            from counted cross join lateral (values
                                (1, 'New', counted.fresh), (2, 'Came back', counted.back), (3, 'Stopped', -counted.lost)
                            ) as value(position, series, y)
                            order by value.position, counted.bucket
                        `,
                    },
                    {
                        id: "sync_churn_rate", title: "Weekly and monthly sync churn", kind: "line", unit: "percent", x: "date",
                        definition: `Weekly sync churn: of the people whose phone synced Apple Health steps in the 7 days before the last 7, the share whose phone synced no day in the last 7. Monthly: the same with 30 days. Each point reads the complete days up to the end of its ${w.bucket}. A point shows only when at least 10 people synced in the earlier days. A phone stops syncing when the app is deleted or Health is turned off. A phone that comes back uploads the days it missed, so older points drop when people return.`,
                        example: (r) => {
                            const weekly = r.at("Weekly churn");
                            const monthly = r.at("Monthly churn");
                            if (weekly === undefined) return null;
                            return `Weekly sync churn was ${r.format(weekly)} ${r.when}${monthly === undefined ? "" : `, and monthly sync churn ${r.format(monthly)}`}.`;
                        },
                        note: `Phone stopped syncing steps: app deleted or Health off. Complete days up to the end of each ${w.bucket}.`,
                        query: churnLines(synced),
                    },
                    {
                        id: "churn_by_fight", title: "Weekly churn, in a fight or not", kind: "bar", unit: "percent", x: "label",
                        definition: `People who opened the app 8 to 14 days ago, split by whether they were in a live fight when the last 7 complete days started. Each bar is the share who did not open the app in those 7 days. The app-wide Fight and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count. ${kept}, so it shows from 16 Oct.`,
                        example: (r) => {
                            const fighting = r.row("In a live fight");
                            const idle = r.row("No live fight");
                            if (fighting === undefined || idle === undefined) return null;
                            return `${r.format(fighting)} of the people in a live fight stopped opening the app in the last 7 days, against ${r.format(idle)} of the people with no live fight.`;
                        },
                        note: "Opened the app 8 to 14 days ago. Fight status when the last 7 days started.",
                        query: sql`
                            with people as (
                                select a.user_id, bool_or(a.day >= ${w.today}::date - 7) as stayed
                                from (${opened}) as a
                                where a.day >= ${w.today}::date - 14 and a.day < ${w.today}::date
                                group by a.user_id
                                having bool_or(a.day < ${w.today}::date - 7)
                            ),
                            grouped as (
                                select people.stayed, exists (
                                    select 1 from public.fight_members as m join (${userFights}) as f on f.id = m.fight_id
                                    where m.user_id = people.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host
                                        and f.state not in ('draft', 'cancelled')
                                        and f.starts_at <= (${w.today}::date - 7)::timestamp at time zone 'Europe/Paris'
                                        and f.ends_at > (${w.today}::date - 7)::timestamp at time zone 'Europe/Paris'
                                ) as fighting
                                from people
                            )
                            select band.x, (100.0 * count(*) filter (where not grouped.stayed) / count(*))::float8 as y
                            from (values (1, 'In a live fight', true), (2, 'No live fight', false)) as band(position, x, fighting)
                            join grouped on grouped.fighting = band.fighting
                            where ${w.today}::date - 14 >= ${openedFrom}
                            group by band.position, band.x
                            order by band.position
                        `,
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
                        definition: `People who opened the app at least once in the last 24 hours, compared with the 24 hours before. Each person counts once. ${background}`,
                        example: (r) => `${r.count(r.value, "person", "people")} opened the app in the last 24 hours${r.against("in the 24 hours before")}.`,
                        query: eventCard(sql, w, 1, activity, people, openedFrom),
                    },
                    weeklyActive, monthlyActive,
                    {
                        id: "stickiness", title: "Monthly stickiness", unit: "percent", better: true,
                        note: `Average daily actives divided by monthly actives, the 30 complete days before today vs the 30 before. ${kept}, so until 1 Nov it reads the days since then.`,
                        definition: `Average daily active users divided by the people active in the same days, over the 30 complete days before today, compared with the 30 days before. It is also the share of days an active person opens the app: 100% means every day. ${kept}, so until 1 Nov it reads the complete days since then, and the comparison shows from 1 Dec.`,
                        example: (r) => `On an average complete day of the last 30, ${r.format(r.value)} of the people active in that time opened the app${r.against("for the 30 days before")}.`,
                        query: sql`
                            select 100.0 * count(*) filter (where e.day >= greatest(${w.today}::date - 30, ${openedFrom}))
                                    / (${w.today}::date - greatest(${w.today}::date - 30, ${openedFrom}))
                                    / nullif(count(distinct e.user_id) filter (
                                        where e.day >= greatest(${w.today}::date - 30, ${openedFrom})), 0) as value,
                                case when ${w.today}::date - 60 >= ${openedFrom}
                                    then 100.0 * count(*) filter (where e.day < ${w.today}::date - 30) / 30
                                        / nullif(count(distinct e.user_id) filter (where e.day < ${w.today}::date - 30), 0)
                                end as previous
                            from (${activeDays}) as e
                            where e.day >= ${w.today}::date - 60 and e.day < ${w.today}::date
                        `,
                    },
                    weeklyOpens,
                    {
                        id: "opens_per_active", title: "Weekly opens per active user", unit: "count", better: true,
                        note: "App opens divided by people who opened the app, last 7 days vs the 7 before.",
                        definition: `App opens in the last 7 days divided by the people who opened the app, compared with the 7 days before. It shows how often an active person comes back. ${kept}, so the comparison shows from 16 Oct.`,
                        example: (r) => `Each active person opened the app ${r.count(r.value, "time", "times")} on average in the last 7 days${r.against("in the 7 days before")}.`,
                        query: sql`
                            select count(*) filter (where e.trigger = 'foreground' and e.at >= ${ago(7)})::float8
                                    / nullif(count(distinct e.user_id) filter (where e.at >= ${ago(7)}), 0) as value,
                                case when ${ago(14)} >= ${openedFrom}::timestamp at time zone 'Europe/Paris' then
                                    count(*) filter (where e.trigger = 'foreground' and e.at >= ${ago(14)} and e.at < ${ago(7)})::float8
                                        / nullif(count(distinct e.user_id) filter (where e.at >= ${ago(14)} and e.at < ${ago(7)}), 0)
                                end as previous
                            from (${activity}) as e where e.at < ${w.now}
                        `,
                    },
                    {
                        id: "returning", title: "Weekly return rate", unit: "percent", better: true,
                        note: "Share of the previous 7 days' active people who were active again in the last 7.",
                        definition: `Of the people who opened the app 7 to 14 days ago, the share who opened it again in the last 7 days. The comparison is the same share one week earlier. ${kept}, so the comparison shows from 23 Oct.`,
                        example: (r) => `${r.format(r.value)} of the people active 7 to 14 days ago came back in the last 7 days${r.against("a week earlier")}.`,
                        query: sql`
                            with periods as (
                                select distinct e.user_id,
                                    case when e.at >= ${ago(7)} then 0 when e.at >= ${ago(14)} then 1 else 2 end as period
                                from (${activity}) as e where e.at >= ${ago(21)} and e.at < ${w.now}
                            )
                            select 100.0 * count(*) filter (where p.period = 1 and exists (
                                        select 1 from periods as q where q.user_id = p.user_id and q.period = 0))
                                    / nullif(count(*) filter (where p.period = 1), 0) as value,
                                case when ${ago(21)} >= ${openedFrom}::timestamp at time zone 'Europe/Paris' then
                                    100.0 * count(*) filter (where p.period = 2 and exists (
                                            select 1 from periods as q where q.user_id = p.user_id and q.period = 1))
                                        / nullif(count(*) filter (where p.period = 2), 0)
                                end as previous
                            from periods as p
                        `,
                    },
                    {
                        id: "lapsed", title: "Lapsed for 14+ days", unit: "count", better: false,
                        note: "Opened the app before, not in the last 14 days. Now vs 7 days ago.",
                        definition: "People who opened the app in the last 120 days, but not in the last 14 days, compared with the same count 7 days ago. Opens are recorded from 16 Sep 2026, so someone who stopped before then is not counted.",
                        example: (r) => `${r.count(r.value, "person who used the app in the last 120 days has", "people who used the app in the last 120 days have")} not opened it for 14 days or more${r.against("a week ago")}.`,
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
                        note: `Average days each active person opened the app, the 30 complete days before today vs the 30 before. ${kept}, so until 1 Nov it reads the days since then.`,
                        definition: `The average number of days each active person opened the app in the 30 complete days before today, compared with the 30 days before. ${kept}, so until 1 Nov it counts the complete days since then, and the comparison shows from 1 Dec.`,
                        example: (r) => `An active person opened the app on ${r.format(r.value)} on average in the last 30 complete days${r.against("in the 30 days before")}.`,
                        query: sql`
                            select count(*) filter (where e.day >= greatest(${w.today}::date - 30, ${openedFrom}))::float8
                                    / nullif(count(distinct e.user_id) filter (
                                        where e.day >= greatest(${w.today}::date - 30, ${openedFrom})), 0) as value,
                                case when ${w.today}::date - 60 >= ${openedFrom}
                                    then count(*) filter (where e.day < ${w.today}::date - 30)::float8
                                        / nullif(count(distinct e.user_id) filter (where e.day < ${w.today}::date - 30), 0)
                                end as previous
                            from (${activeDays}) as e
                            where e.day >= ${w.today}::date - 60 and e.day < ${w.today}::date
                        `,
                    },
                ],
                charts: [
                    {
                        id: "dau_wau_mau", title: "Daily, weekly and monthly active users", kind: "line", unit: "count", x: "date",
                        definition: w.bucket === "day"
                            ? `DAU: people who opened the app that day. WAU and MAU: people who opened it at least once in the 7 or 30 days up to that day. ${kept}, so DAU starts then, WAU on 8 Oct and MAU on 31 Oct.`
                            : `DAU: people who opened the app on a day, averaged over the days of each ${w.bucket}. WAU and MAU: people who opened it at least once in the 7 or 30 days up to the end of the ${w.bucket}. ${kept}, so earlier ${w.bucket}s are left out, WAU starts on 8 Oct and MAU on 31 Oct.`,
                        example: (r) => {
                            const daily = r.at("DAU");
                            const weekly = r.at("WAU");
                            const monthly = r.at("MAU");
                            if (daily === undefined || weekly === undefined) return null;
                            const opened = w.bucket === "day"
                                ? `${r.count(daily, "person", "people")} opened the app ${r.when}`
                                : `${r.format(daily)} people opened the app on an average day ${r.when}`;
                            return `${opened}. ${r.format(weekly)} opened it in the 7 days up to then${monthly === undefined ? "" : `, and ${r.format(monthly)} in the 30 days`}.`;
                        },
                        note: w.bucket === "day"
                            ? `WAU and MAU count the 7 and 30 days up to each day. ${kept}: WAU starts on 8 Oct, MAU on 31 Oct.`
                            : `DAU is the daily average in each ${w.bucket}. WAU and MAU count the 7 and 30 days up to its end, now for the last one. ${kept}: WAU starts on 8 Oct, MAU on 31 Oct.`,
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
                                (1, 'DAU', counted.daily, 0), (2, 'WAU', counted.weekly, 6), (3, 'MAU', counted.monthly, 29)
                            ) as value(position, series, y, reach)
                            where counted.day >= (select min(day) from active) and counted.bucket >= ${openedFrom}
                                and counted.day - value.reach >= ${openedFrom}
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
                        note: `App opens divided by people who opened the app in each ${w.bucket}. ${kept}; earlier ${w.bucket}s are left out.`,
                        query: perBucket(sql, w, activity, sql`
                            count(*) filter (where e.trigger = 'foreground')::float8 / nullif(count(distinct e.user_id), 0)
                        `, { gaps: true, from: openedFrom }),
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
                        note: `New: signed up in the same ${w.bucket}. ${kept}; earlier ${w.bucket}s are left out.`,
                        query: perBucket(sql, w, sql`
                            select a.user_id, a.at, case when date_trunc(${w.bucket}::text, p.joined_day::timestamp)
                                = date_trunc(${w.bucket}::text, (a.at at time zone 'Europe/Paris')::date::timestamp)
                                then 'New' else 'Returning' end as series
                            from (${activity}) as a join (${profiles}) as p using (user_id)
                        `, people, { gaps: true, series: ["New", "Returning"], from: openedFrom }),
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
                        note: `Among people who opened the app that day${w.bucket === "day" ? "" : `, across each ${w.bucket}`}. ${kept}; earlier ${w.bucket}s are left out.`,
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
                                from daily where date_trunc(${w.bucket}::text, day::timestamp)::date >= ${openedFrom} group by 1
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
                        note: `People by how many of the last 30 days they opened the app. ${kept}, so until 31 Oct the higher groups read low.`,
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
                        definition: "Every user by the days since they last opened the app. Never means no open recorded in the last 120 days. Opens are recorded from 16 Sep 2026, so Never includes people who last opened the app before then.",
                        example: (r) => {
                            const today = r.row("Today") ?? 0;
                            const never = r.row("Never") ?? 0;
                            return r.total > 0
                                ? `${r.count(today, "person", "people")} opened the app today, and ${r.format(never)} have no open in the last 120 days.`
                                : null;
                        },
                        note: "Never: no open recorded in the last 120 days, or since recording began on 16 Sep 2026.",
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
                        definition: "Each cell is the number of different people who opened the app at least once on that weekday at that hour in the last 30 days, in their saved time zone. Someone who opens it often counts once per cell. People without a saved time zone, most accounts created before 28 Sep 2026, are placed in Paris time, so evening opens in the Americas show as Paris night. The darker the cell, the more people.",
                        example: (r) => (r.peak && r.peak.value > 0
                            ? `The busiest time is ${r.peak.y} ${r.peak.x}:00 local time: ${r.count(r.peak.value, "person", "people")} opened the app then in the last 30 days.`
                            : null),
                        note: "People who opened the app, by weekday and hour in their saved time zone, else Paris time.",
                        query: sql`
                            with zones as (select name from pg_timezone_names),
                            counted as (
                                select extract(isodow from local.at)::int as d, extract(hour from local.at)::int as h,
                                    count(distinct o.user_id) as n
                                from (${opens}) as o
                                join public.profiles as p on p.user_id = o.user_id
                                left join zones on zones.name = p.time_zone
                                cross join lateral (select o.at at time zone coalesce(zones.name, 'Europe/Paris') as at) as local
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
                        definition: `People who opened the app the most in the last 30 days. ${kept}, so until 1 Nov earlier opens are missing.`,
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
                        note: "Per person-day, the 7 complete days before today vs the 7 before. New signups count.",
                        definition: "Average steps per person per day over the 7 complete days before today, compared with the 7 days before. Each person's complete Apple Health days count, from their signup day.",
                        example: (r) => `The average person walked ${r.format(r.value)} steps a day in the last 7 complete days${r.against("in the 7 days before")}.`,
                        query: dayCard(sql, w, 7, recentSteps, sql`avg(e.steps)`),
                    },
                    {
                        id: "median_steps", title: "Weekly median daily steps", unit: "steps", better: true,
                        note: "Per person-day, the 7 complete days before today vs the 7 before.",
                        definition: "The median steps per person-day over the 7 complete days before today, compared with the 7 days before. A person-day is one person's complete day of Apple Health steps. Half of the person-days were above the median. Unlike the average, a few big walkers do not pull it up.",
                        example: (r) => `Half of the person-days in the last 7 complete days had ${r.format(r.value)} steps or more${r.against("in the 7 days before")}.`,
                        query: dayCard(sql, w, 7, recentSteps, sql`percentile_cont(0.5) within group (order by e.steps)`),
                    },
                    {
                        id: "walkers", title: "Weekly walkers", unit: "count", better: true,
                        note: "People with step data in the 7 days before today, vs the 7 before. New signups count.",
                        definition: "People with at least one complete day of Apple Health steps in the 7 complete days before today, compared with the 7 days before.",
                        example: (r) => `${r.count(r.value, "person", "people")} had step data in the last 7 complete days${r.against("in the 7 days before")}.`,
                        query: dayCard(sql, w, 7, recentSteps, people),
                    },
                    {
                        id: "ten_k_days", title: "Weekly 10K-step days", unit: "percent", better: true,
                        note: "Share of person-days with 10,000 steps or more, last 7 days vs the 7 before.",
                        definition: "The share of person-days with 10,000 steps or more over the 7 complete days before today, compared with the 7 days before. A person-day is one person's complete day of Apple Health steps.",
                        example: (r) => `${r.format(r.value)} of person-days reached 10,000 steps in the last 7 complete days${r.against("in the 7 days before")}.`,
                        query: dayCard(sql, w, 7, recentSteps, sql`avg(case when e.steps >= 10000 then 100.0 else 0 end)`),
                    },
                    {
                        id: "fight_day_lift", title: "Monthly fight-day lift", unit: "percent", better: true,
                        note: "Median person: steps on their days in a live Fight vs their other days. Last 30 days vs the 30 before.",
                        definition: "For each person, how many more steps they walk on days in a live Fight than on their own other days, in percent, over the 30 complete days before today. The card shows the median person, compared with the 30 days before. Only people with 3 or more days of each kind count, and a window shows no number until 5 people do. A Fight counts from the day the person accepted it, and only with another accepted member. The app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count.",
                        example: (r) => `The median person walked ${r.format(Math.abs(r.value))} ${r.value < 0 ? "fewer" : "more"} steps on fight days than on their other days in the last 30 complete days${r.against("in the 30 days before")}.`,
                        query: sql`
                            with people as (
                                select case when e.day >= ${w.today}::date - 30 then 'value' else 'previous' end as period,
                                    100.0 * (avg(e.steps) filter (where e.in_fight)
                                        / nullif(avg(e.steps) filter (where not e.in_fight), 0) - 1) as lift
                                from (${fightDays}) as e
                                where e.day >= ${w.today}::date - 60
                                group by 1, e.user_id
                                having count(*) filter (where e.in_fight) >= 3 and count(*) filter (where not e.in_fight) >= 3
                            )
                            select case when count(lift) filter (where period = 'value') >= 5
                                    then percentile_cont(0.5) within group (order by lift) filter (where period = 'value') end as value,
                                case when count(lift) filter (where period = 'previous') >= 5
                                    then percentile_cont(0.5) within group (order by lift) filter (where period = 'previous') end as previous
                            from people
                        `,
                    },
                    {
                        id: "joining_lift", title: "Change after joining", unit: "percent", better: true,
                        note: "All time. Median of each person's 4 full weeks after signup vs the 4 before.",
                        definition: "For each person who signed up more than 4 weeks ago, the change in average daily steps from the 4 weeks before signup to the 4 weeks after the signup day, from Apple Health history. The signup day itself is left out. Only people with 20 or more days of data on each side count. The card shows the median person, all time. There is no comparison.",
                        example: (r) => `The median person walks ${r.format(Math.abs(r.value))} ${r.value < 0 ? "less" : "more"} in the 4 weeks after signing up than in the 4 weeks before.`,
                        query: sql`
                            with compared as (
                                select user_id,
                                    avg(steps) filter (where day >= joined_day - 28 and day < joined_day) as before,
                                    avg(steps) filter (where day > joined_day and day <= joined_day + 28) as after
                                from (${history}) as h
                                where joined_day + 28 < ${w.today}::date
                                group by user_id
                                having count(*) filter (where day >= joined_day - 28 and day < joined_day) >= 20
                                    and count(*) filter (where day > joined_day and day <= joined_day + 28) >= 20
                            )
                            select percentile_cont(0.5) within group (order by 100.0 * (after / nullif(before, 0) - 1)) as value,
                                null::float8 as previous
                            from compared where before > 0
                        `,
                    },
                    {
                        id: "all_time_steps", title: "All-time steps", unit: "steps", better: true,
                        note: "Every complete day since each person joined. Now vs 7 days ago.",
                        definition: "Every Apple Health step people walked since their signup day, complete days only, compared with the same total 7 days ago.",
                        example: (r) => `FitFight people have walked ${r.format(r.value)} steps since they signed up${r.against("a week ago")}.`,
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
                        definition: "Average steps per person-day on days when the person was in a live Fight, against their days without one. Both lines are the same people: those with 3 or more days of each kind in the period. A Fight counts from the day the person accepted it, and only with another accepted member. The app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count.",
                        example: (r) => {
                            const fighting = r.at("In a fight");
                            const other = r.at("Other days");
                            return fighting === undefined || other === undefined ? null
                                : `People in a fight walked ${r.format(fighting)} steps a day ${r.when}, against ${r.format(other)} on other days.`;
                        },
                        note: `Average steps per person-day${w.bucket === "day" ? "" : ` in each ${w.bucket}`}, on days in a live Fight vs days without one. Only people with 3+ days of each kind in the period.`,
                        query: perBucket(sql, w, sql`
                            select * from (
                                select d.*, case when d.in_fight then 'In a fight' else 'Other days' end as series,
                                    count(*) filter (where d.in_fight) over (partition by d.user_id) as fighting,
                                    count(*) filter (where not d.in_fight) over (partition by d.user_id) as other
                                from (${fightDays}) as d
                                where d.day >= ${w.start}::date
                            ) as d
                            where d.fighting >= 3 and d.other >= 3
                        `, sql`avg(e.steps)`, { complete: true, gaps: true, series: ["In a fight", "Other days"] }),
                    },
                    {
                        id: "people_by_average", title: "People by daily average, last 30 days", kind: "bar", unit: "count", x: "label",
                        definition: "People by their average daily steps over the last 30 complete days. Only people with 7 or more complete days of steps in those 30 count.",
                        example: (r) => {
                            const active = (r.row("10K-15K") ?? 0) + (r.row("15K+") ?? 0);
                            const part = r.share(active, r.total);
                            return part
                                ? `${r.count(active, "person averages", "people average")} 10,000 steps a day or more: ${part} of everyone with 7 or more days of step data.`
                                : null;
                        },
                        query: sql`
                            with people as (
                                select user_id, avg(steps) as steps from (${recentSteps}) as s
                                where s.day >= ${w.today}::date - 30 group by 1 having count(*) >= 7
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
                        definition: "Average steps per person on each day around signup, from Apple Health history. Only people with 7 or more days of data both in the 4 weeks before signup and in the 4 weeks after the signup day, so both sides are the same people. Day 0 is the signup day; negative days are before it. A day with fewer than 20 people is left out.",
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
                        note: "Day 0 is the signup day. People with 7+ days of history on each side; days with under 20 people are left out.",
                        query: sql`
                            select (day - joined_day)::text as x, avg(steps)::float8 as y
                            from (
                                select h.*,
                                    count(*) filter (where h.day - h.joined_day between -28 and -1) over (partition by h.user_id) as before,
                                    count(*) filter (where h.day - h.joined_day between 1 and 28) over (partition by h.user_id) as after
                                from (${history}) as h
                            ) as h
                            where day - joined_day between -28 and 28 and before >= 7 and after >= 7
                            group by day - joined_day having count(*) >= 20 order by day - joined_day
                        `,
                    },
                    {
                        id: "joining_change_distribution", title: "Change after joining, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People by how their average steps changed: the 4 weeks after the signup day against the 4 weeks before signup. Only people who signed up more than 4 weeks ago, with 20 or more days of data on each side.",
                        example: (r) => {
                            const up = (r.row("Up 5-20%") ?? 0) + (r.row("Up 20%+") ?? 0);
                            return r.total > 0
                                ? `${r.count(up, "person walks", "people walk")} at least 5% more since joining, out of ${r.format(r.total)}.`
                                : null;
                        },
                        note: "People by their 4 full weeks after signup vs the 4 weeks before (20+ days of data each side).",
                        query: sql`
                            with compared as (
                                select 100.0 * (avg(steps) filter (where day > joined_day and day <= joined_day + 28)
                                    / nullif(avg(steps) filter (where day >= joined_day - 28 and day < joined_day), 0) - 1) as change
                                from (${history}) as h
                                where joined_day + 28 < ${w.today}::date
                                group by user_id
                                having count(*) filter (where day >= joined_day - 28 and day < joined_day) >= 20
                                    and count(*) filter (where day > joined_day and day <= joined_day + 28) >= 20
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
                        definition: "Fight rounds with two or more fighters that ended with results in the last 7 days, up to now, compared with the 7 days before. Every round of a repeating Fight counts, the app-wide Fight included. Rounds with one fighter, founder Fights and friend Fights do not. A round counts once its final sync is done.",
                        example: (r) => `${r.count(r.value, "round", "rounds")} finished in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select f.ends_at as at from (${rounds}) as f where f.state = 'final'`, count),
                    },
                    {
                        id: "joins", title: "Weekly fight joins", unit: "count", better: true,
                        note: "People joining someone else's Fight, app-wide, founder and friend ones excluded. Last 7 days vs the 7 before.",
                        definition: "How many times people joined someone else's Fight in the last 7 days, up to now, compared with the 7 days before. A repeating Fight carries its fighters into each new round; that is not a join. The app-wide Fight, suggested Fights, founder Fights and friend Fights do not count.",
                        example: (r) => `People joined someone else's fight ${r.count(r.value, "time", "times")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, joins, count),
                    },
                    {
                        id: "people_in_fights", title: "Users in a live fight", unit: "percent", better: true,
                        note: "Share of all users, now vs 7 days ago. App-wide and suggested Fights excluded.",
                        definition: "The share of all users who are in a live Fight now, compared with 7 days ago. A Fight counts once someone besides its owner joins it. The app-wide Fight and suggested Fights do not count; the App-wide and suggested fights chart shows them. Founder Fights count for the challenger only, and friend Fights do not count.",
                        example: (r) => `${r.format(r.value)} of users are in a live fight now${r.against("a week ago")}.`,
                        query: sql`
                            select 100.0 * (select count(distinct m.user_id) from public.fight_members as m
                                    join (${userContests}) as f on f.id = m.fight_id
                                    join public.profiles as p on p.user_id = m.user_id and p.deleted_at is null
                                    where m.state = 'accepted' and m.user_id::text is distinct from f.host and f.starts_at <= ${w.now} and f.ends_at > ${w.now})
                                    / nullif((select count(*) from public.profiles
                                        where deleted_at is null and created_at < ${w.now}), 0) as value,
                                100.0 * (select count(distinct m.user_id) from public.fight_members as m
                                    join (${userContests}) as f on f.id = m.fight_id
                                    join public.profiles as p on p.user_id = m.user_id and p.deleted_at is null
                                        and p.created_at < ${ago(7)}
                                    where m.state = 'accepted' and m.user_id::text is distinct from f.host and m.accepted_at <= ${ago(7)}
                                        and f.starts_at <= ${ago(7)} and f.ends_at > ${ago(7)})
                                    / nullif((select count(*) from public.profiles
                                        where deleted_at is null and created_at < ${ago(7)}), 0) as previous
                        `,
                    },
                    {
                        id: "fighters_per_fight", title: "Monthly fighters per fight", unit: "count", better: true,
                        note: "Average accepted fighters in Fights that started in the last 30 days, vs the 30 before.",
                        definition: "The average number of accepted fighters in the Fights that started in the last 30 days, up to now, compared with the 30 days before. Every round counts. Fights nobody else joined, cancelled Fights, the app-wide Fight, suggested Fights, founder Fights and friend Fights do not.",
                        example: (r) => `Fights that started in the last 30 days had ${r.count(r.value, "fighter", "fighters")} on average${r.against("in the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select f.starts_at as at, (select count(*) from public.fight_members as m
                                where m.fight_id = f.id and m.state = 'accepted') as fighters
                            from (${contests}) as f
                        `, sql`avg(e.fighters)`),
                    },
                    {
                        id: "invite_acceptance", title: "Monthly invite acceptance", unit: "percent", better: true,
                        note: "Share of people invited in the last 30 days who are now in the Fight, vs the 30 before. Invites are logged since 26 Sep 2026.",
                        definition: "Of the invitations sent in the last 30 days, up to now, the share whose invited person is in any round of the Fight now, compared with the 30 days before. Invites are logged since 26 Sep 2026, and joining by code is not an invite, so this rests on few invitations. The app-wide Fight, suggested Fights, founder Fights and friend Fights do not count.",
                        example: (r) => `${r.format(r.value)} of the people invited in the last 30 days are in the fight now${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select event.occurred_at as at, bool_or(m.state = 'accepted') as accepted
                            from private.fight_membership_events as event
                            join (${realFights}) as f on f.id = event.fight_id
                            left join public.fights as round on round.series_id = f.series_id
                            left join public.fight_members as m on m.fight_id = round.id and m.user_id = event.user_id
                            where event.state = 'invited' and event.occurred_at is not null
                            group by event.fight_id, event.user_id, event.occurred_at
                        `, sql`avg(case when e.accepted then 100.0 else 0 end)`),
                    },
                    {
                        id: "cancel_rate", title: "Monthly cancel rate", unit: "percent", better: false,
                        note: "Share of Fights starting in the last 30 days that were cancelled, vs the 30 before.",
                        definition: "Of the Fights due to start in the last 30 days, up to now, the share that were cancelled, compared with the 30 days before. Every round counts. A cancelled Fight counts even when nobody joined it (every cancellation so far is of that kind); a Fight nobody else joined that ran is left out. The app-wide Fight, suggested Fights, founder Fights and friend Fights do not count.",
                        example: (r) => `${r.format(r.value)} of the fights due to start in the last 30 days were cancelled${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select f.starts_at as at, f.state from (${realFights}) as f
                            where f.state = 'cancelled' or f.id in (select contest.id from (${contests}) as contest)
                        `,
                            sql`avg(case when e.state = 'cancelled' then 100.0 else 0 end)`),
                    },
                    {
                        id: "recurring_share", title: "Monthly recurring share", unit: "percent", better: null,
                        note: "Share of new Fights created as recurring, last 30 days vs the 30 before.",
                        definition: "The share of new Fights created as recurring in the last 30 days, up to now, compared with the 30 days before. A recurring Fight starts a new round when one ends. A Fight counts once someone besides its owner joins it. Cancelled Fights, the app-wide Fight, suggested Fights, founder Fights and friend Fights do not count.",
                        example: (r) => `${r.format(r.value)} of the fights created in the last 30 days are recurring${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select created.at, series.recurring from (${firstRounds}) as created
                            join public.fight_series as series on series.id = created.series_id
                        `, sql`avg(case when e.recurring then 100.0 else 0 end)`),
                    },
                    {
                        id: "winning_margin", title: "Monthly winning margin", unit: "percent", better: null,
                        note: "Median lead of the winner over second place, Fights finished in the last 30 days vs the 30 before.",
                        definition: "How far the winner was ahead of second place, as a share of the winner's steps, in the median Fight that finished in the last 30 days, up to now, compared with the 30 days before. Only Fights with two or more fighters count. The app-wide Fight counts. Founder and friend Fights do not.",
                        example: (r) => `In half of the fights that finished in the last 30 days, the winner led second place by ${r.format(r.value)} or less${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select f.ends_at as at, 100.0 * (ranked.first - ranked.second) / nullif(ranked.first, 0) as margin
                            from public.fights as f
                            cross join lateral (
                                select max(m.final_value) filter (where m.rank = 1) as first,
                                    max(m.final_value) filter (where m.rank = 2) as second
                                from public.fight_members as m where m.fight_id = f.id and m.state = 'accepted'
                            ) as ranked
                            where f.state = 'final' and (to_jsonb(f) ->> 'host_id') is null and (to_jsonb(f) ->> 'friends') is distinct from 'true'
                                and ranked.second is not null
                        `, sql`percentile_cont(0.5) within group (order by e.margin)`),
                    },
                ],
                charts: [
                    fightsCreatedChart,
                    {
                        id: "live_fights_over_time", title: "Live fights", kind: "line", unit: "count", x: "date",
                        definition: `Fights running with two or more fighters at the end of each ${w.bucket}, and now for the last point. The app-wide Fight counts. Founder Fights, friend Fights and rounds with one fighter do not.`,
                        example: (r) => {
                            const n = r.latest();
                            return n === undefined ? null : `${r.count(n, "fight is", "fights are")} live now.`;
                        },
                        note: `At the end of each ${w.bucket}, now for the last one. App-wide Fight included, founder and friend Fights and solo rounds not.`,
                        query: sql`
                            select point.bucket::text as x, (
                                select count(*) from (${rounds}) as f
                                where f.state not in ('draft', 'cancelled') and f.starts_at <= point.at and f.ends_at > point.at
                            )::float8 as y
                            from (${instants}) as point order by point.bucket
                        `,
                    },
                    {
                        id: "people_in_fights_over_time", title: "Users in a live fight", kind: "line", unit: "percent", x: "date",
                        definition: `Share of all users who are in a live Fight, at the end of each ${w.bucket} and now for the last point. A Fight counts once someone besides its owner joins it. The app-wide Fight and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count.`,
                        example: (r) => {
                            const n = r.latest();
                            return n === undefined ? null : `${r.format(n)} of users are in a live fight now.`;
                        },
                        note: `Share of all users, at the end of each ${w.bucket}, now for the last one. App-wide and suggested Fights excluded.`,
                        query: sql`
                            select point.bucket::text as x, (100.0 * (
                                select count(distinct m.user_id) from public.fight_members as m
                                join (${userContests}) as f on f.id = m.fight_id
                                join public.profiles as p on p.user_id = m.user_id and p.deleted_at is null and p.created_at < point.at
                                where m.state = 'accepted' and m.user_id::text is distinct from f.host and m.accepted_at <= point.at
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
                        definition: `Fight rounds with two or more fighters that ended with results, in each ${w.bucket}. Every round of a repeating Fight counts, the app-wide Fight included. Rounds with one fighter, founder Fights and friend Fights do not. A round counts once its final sync is done, so the latest days can still grow.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "round", "rounds")} finished ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`select f.ends_at as at from (${rounds}) as f where f.state = 'final'`, count),
                    },
                    {
                        id: "invites_and_joins", title: `Invites and joins ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `Invitations sent to Fights, and people who joined someone else's Fight, in each ${w.bucket}. A repeating Fight carries its fighters into each new round; that is not a join. Invites are logged since 26 Sep 2026, and joining by code is not an invite. App-wide, suggested, founder and friend Fights are not counted.`,
                        example: (r) => {
                            const sent = r.at("Invites sent");
                            const joined = r.at("People joining");
                            return sent === undefined || joined === undefined ? null
                                : `${r.count(sent, "invite was", "invites were")} sent ${r.when}, and ${r.count(joined, "person", "people")} joined a fight.`;
                        },
                        note: "App-wide, suggested, founder and friend Fights excluded. Invites logged since 26 Sep 2026.",
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
                        definition: "Fights with a round that started in the last 30 days, by the accepted fighters in their latest such round. A repeating Fight counts once. Solo means nobody else joined. Cancelled, app-wide, suggested, founder and friend Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0
                            ? `${r.top.x}${/^\d+(-\d+|\+)$/.test(r.top.x) ? " fighters" : ""} is the most common size: ${r.count(r.top.y, "fight", "fights")} out of ${r.format(r.total)}.`
                            : null),
                        note: "Fights with a round started in the last 30 days, by accepted fighters. Each Fight once.",
                        query: sql`
                            with sizes as (
                                select distinct on (f.series_id) (select count(*) from public.fight_members as m
                                    where m.fight_id = f.id and m.state = 'accepted') as fighters
                                from (${realFights}) as f
                                where f.state <> 'cancelled' and f.starts_at >= ${ago(30)} and f.starts_at < ${w.now}
                                order by f.series_id, f.starts_at desc
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
                        definition: "How long Fights last, all time. A Fight counts once someone besides its owner joins it. Cancelled, app-wide, suggested, founder and friend Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} is the most common length: ${r.count(r.top.y, "fight", "fights")} out of ${r.format(r.total)}.` : null),
                        query: sql`
                            select duration.x, count(series.id)::float8 as y from (values
                                (1, 'Up to 1 day', 0, 86400), (2, '2-3 days', 86401, 259200), (3, '4-7 days', 259201, 604800),
                                (4, '8-14 days', 604801, 1209600), (5, '15-31 days', 1209601, 2678400), (6, 'Longer', 2678401, 2147483647)
                            ) as duration(position, x, low, high)
                            left join public.fight_series as series on series.duration_seconds between duration.low and duration.high
                                and series.id in (select contest.series_id from (${contests}) as contest)
                            group by duration.position, duration.x order by duration.position
                        `,
                    },
                    {
                        id: "margins", title: "How close fights end, all time", kind: "bar", unit: "count", x: "label",
                        definition: "Finished Fights with two or more fighters, by how far the winner was ahead of second place, as a share of the winner's steps. The app-wide Fight counts. Founder and friend Fights do not.",
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
                                where f.state = 'final' and (to_jsonb(f) ->> 'host_id') is null and (to_jsonb(f) ->> 'friends') is distinct from 'true'
                                and ranked.second is not null
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
                        definition: "Every user by the time between signing up and first joining a fight. Not yet means they have not joined one, even if they are in the app-wide Fight. Creating a fight counts once someone else joins it. Cancelled, app-wide and suggested Fights do not count. Founder Fights count for the challenger only, and friend Fights do not count.",
                        example: (r) => {
                            const soon = r.row("Under 1 day") ?? 0;
                            const waiting = r.row("Not yet") ?? 0;
                            return r.total > 0
                                ? `${r.count(soon, "person", "people")} joined a fight within a day of signing up, and ${r.format(waiting)} have not joined one yet.`
                                : null;
                        },
                        query: sql`
                            with waits as (
                                select extract(epoch from (
                                    select min(m.accepted_at) from public.fight_members as m
                                    join (${userContests}) as f on f.id = m.fight_id
                                    where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host
                                ) - p.created_at) / 86400 as days
                                from public.profiles as p where p.deleted_at is null
                            )
                            select band.x, (case when band.position = 6 then (select count(*) from waits where days is null)
                                else (select count(*) from waits where greatest(days, 0) >= band.low and days < band.high) end)::float8 as y
                            from (values
                                (1, 'Under 1 day', 0, 1), (2, '1-3 days', 1, 4), (3, '4-7 days', 4, 8),
                                (4, '8-30 days', 8, 31), (5, '31+ days', 31, 1000000), (6, 'Not yet', 0, 0)
                            ) as band(position, x, low, high) order by band.position
                        `,
                    },
                    {
                        id: "top_fighters", title: "Most fights joined, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People who joined the most Fights, all time. A repeating Fight counts once, and creating a fight counts once someone else joins it. Cancelled, app-wide, suggested, founder and friend Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} joined ${r.count(r.top.y, "fight", "fights")}.` : null),
                        query: sql`
                            select '@' || p.handle as x, count(distinct f.series_id)::float8 as y
                            from public.fight_members as m join (${contests}) as f on f.id = m.fight_id
                            join public.profiles as p on p.user_id = m.user_id
                            where m.state = 'accepted' group by p.handle order by 2 desc, 1 limit 10
                        `,
                    },
                    {
                        id: "top_winners", title: "Most wins, all time", kind: "bar", unit: "count", x: "label",
                        definition: "People who won the most finished Fights that had at least two fighters, all time. App-wide, suggested, founder and friend Fights are not counted.",
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
                        definition: "The actions losers most often have to do, as people typed them, all time. Most are typed once, so ties show the newest first. A Fight counts once someone besides its owner joins it. Cancelled, app-wide, suggested, founder and friend Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" is the most common action, in ${r.count(r.top.y, "fight", "fights")}.` : null),
                        query: sql`
                            select left(lower(trim(series.action_text)), 40) as x, count(*)::float8 as y
                            from public.fight_series as series
                            where series.action_text is not null and trim(series.action_text) <> ''
                                and series.id in (select contest.series_id from (${contests}) as contest)
                            group by 1 order by 2 desc, max(series.created_at) desc limit 10
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
                    {
                        id: "posts", title: "Weekly posts", unit: "count", better: true, note: weekly,
                        definition: "Posts written in Fight feeds in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `People wrote ${r.count(r.value, "post", "posts")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, posts, count),
                    },
                    {
                        id: "comments", title: "Weekly comments", unit: "count", better: true, note: weekly,
                        definition: "Comments written on Fight feed posts in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `People wrote ${r.count(r.value, "comment", "comments")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, comments, count),
                    },
                    {
                        id: "reactions", title: "Weekly reactions", unit: "count", better: true, note: weekly,
                        definition: "Emoji reactions left on Fight feed posts in the last 7 days, up to now, compared with the 7 days before. Only reactions still on posts count: a removed reaction is gone, and changing the emoji dates it again.",
                        example: (r) => `People left ${r.count(r.value, "reaction", "reactions")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, reactions, count),
                    },
                    {
                        id: "posters", title: "Weekly people posting", unit: "count", better: true,
                        note: "Wrote a post or a comment in the last 7 days, vs the 7 before.",
                        definition: "People who wrote at least one post or comment in Fight feeds in the last 7 days, up to now, compared with the 7 days before. Each person counts once.",
                        example: (r) => `${r.count(r.value, "person", "people")} wrote a post or a comment in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`${posts} union all ${comments}`, people),
                    },
                    {
                        id: "feedback_items", title: "Weekly bugs and requests", unit: "count", better: null, note: weekly,
                        definition: "New bug reports and feature requests on the Feedback tab in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `People filed ${r.count(r.value, "bug or request", "bugs and requests")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select author_id as user_id, created_at as at from public.feedback_posts`, count),
                    },
                    {
                        id: "feedback_votes", title: "Weekly feedback votes", unit: "count", better: true, note: weekly,
                        definition: "Votes on bugs and requests on the Feedback tab in the last 7 days, up to now, compared with the 7 days before. Only votes still standing count: an undone vote is gone.",
                        example: (r) => `People cast ${r.count(r.value, "vote", "votes")} on bugs and requests in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select user_id, created_at as at from public.feedback_votes`, count),
                    },
                    {
                        id: "friendships", title: "Weekly new friendships", unit: "count", better: true, note: weekly,
                        definition: "Friend requests accepted in the last 7 days, up to now, compared with the 7 days before. Only friendships still in place count: a removed friendship is gone.",
                        example: (r) => `${r.count(r.value, "new friendship", "new friendships")} started in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, friendships, count),
                    },
                    {
                        id: "reports", title: "Weekly post reports", unit: "count", better: false, note: weekly,
                        definition: "Reports on Fight feed posts in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `People reported posts ${r.count(r.value, "time", "times")} in the last 7 days${r.against("in the 7 days before")}.`,
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
                        definition: "The most used reactions in the last 30 days, among reactions still on posts.",
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
                        definition: "Fights with the most posts in their feed, all time, with their join code. A repeating Fight counts once, with the posts of every round, and a post shared to several Fights counts in each. Founder Fights are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} has ${r.count(r.top.y, "post", "posts")}.` : null),
                        query: sql`
                            select left(series.name, 32) || ' · ' || series.join_code as x, count(distinct shown.post_id)::float8 as y
                            from (
                                select channel.post_id, posted.series_id from public.fight_post_channels as channel
                                join public.fights as posted on posted.id = channel.fight_id
                                union
                                select post.id, origin.series_id from public.fight_posts as post
                                join public.fights as origin on origin.id = post.fight_id
                                where post.audience = 'fight'
                            ) as shown
                            join public.fight_series as series on series.id = shown.series_id
                            where (to_jsonb(series) ->> 'host_id') is null
                            group by series.id, series.name, series.join_code order by 2 desc, 1 limit 10
                        `,
                    },
                ],
            };
        }
        case "friends": {
            const pairs = peopleRules(sql).friendPairs;
            const friendships = sql`select * from (${pairs}) as pair where pair.state = 'accepted'`;
            // Every user's friends now and 7 days ago.
            const friendCounts = sql`
                select p.user_id, p.created_at,
                    count(*) filter (where side.state = 'accepted') as friends,
                    count(*) filter (where side.accepted_at < ${ago(7)}) as friends_before
                from (${profiles}) as p
                left join (
                    select user_low as user_id, state, accepted_at from (${pairs}) as pair
                    union all select user_high, state, accepted_at from (${pairs}) as pair
                ) as side on side.user_id = p.user_id
                group by p.user_id, p.created_at
            `;
            const kept = "Declining or removing a friend deletes the request, so only requests still pending or accepted count";
            return {
                cards: [
                    {
                        id: "friendships_total", title: "Friendships", unit: "count", better: true,
                        note: "Pairs of friends now, vs 7 days ago.",
                        definition: "Pairs of friends now, each pair counted once, compared with 7 days ago. Deleted accounts and blocked pairs are not counted. Removing a friend deletes the pair, so 7 days ago only counts pairs that are still friends.",
                        example: (r) => `FitFight has ${r.count(r.value, "pair of friends", "pairs of friends")} now${r.against("a week ago")}.`,
                        query: sql`
                            select count(*)::float8 as value, count(*) filter (where accepted_at < ${ago(7)})::float8 as previous
                            from (${friendships}) as pair
                        `,
                    },
                    {
                        id: "new_friendships", title: "Weekly new friendships", unit: "count", better: true,
                        note: "Requests accepted in the last 7 days, vs the 7 before.",
                        definition: "Friend requests accepted in the last 7 days, up to now, compared with the 7 days before. Friendships removed since are not counted.",
                        example: (r) => `${r.count(r.value, "new friendship", "new friendships")} started in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select accepted_at as at from (${friendships}) as pair`, count),
                    },
                    {
                        id: "average_friends", title: "Average friends per user", unit: "count", better: true,
                        note: "All users, now vs 7 days ago.",
                        definition: "The average number of friends per user now, people with no friends included, compared with 7 days ago. Deleted accounts and blocked pairs are not counted.",
                        example: (r) => `The average user has ${r.count(r.value, "friend", "friends")} now${r.against("a week ago")}.`,
                        query: sql`
                            select avg(c.friends)::float8 as value,
                                (avg(c.friends_before) filter (where c.created_at < ${ago(7)}))::float8 as previous
                            from (${friendCounts}) as c
                        `,
                    },
                    {
                        id: "median_friends", title: "Median friends, people with friends", unit: "count", better: true,
                        note: "Among users with at least one friend, now vs 7 days ago.",
                        definition: "The median number of friends among the users who have at least one, now, compared with 7 days ago. Half of them have that many or more. People with no friends are left out here; the share of users with a friend is its own card.",
                        example: (r) => `Half of the users with a friend have ${r.count(r.value, "friend", "friends")} or more${r.against("a week ago")}.`,
                        query: sql`
                            select (percentile_cont(0.5) within group (order by c.friends) filter (where c.friends > 0))::float8 as value,
                                (percentile_cont(0.5) within group (order by c.friends_before)
                                    filter (where c.friends_before > 0))::float8 as previous
                            from (${friendCounts}) as c
                        `,
                    },
                    {
                        id: "with_friend", title: "Users with a friend", unit: "percent", better: true,
                        note: "Share of all users, now vs 7 days ago.",
                        definition: "The share of all users with at least one friend now, compared with 7 days ago. Deleted accounts and blocked pairs are not counted.",
                        example: (r) => `${r.format(r.value)} of users have at least one friend now${r.against("a week ago")}.`,
                        query: sql`
                            select 100.0 * count(*) filter (where c.friends > 0) / nullif(count(*), 0) as value,
                                100.0 * count(*) filter (where c.friends_before > 0)
                                    / nullif(count(*) filter (where c.created_at < ${ago(7)}), 0) as previous
                            from (${friendCounts}) as c
                        `,
                    },
                    {
                        id: "requests_sent", title: "Weekly friend requests", unit: "count", better: true,
                        note: "Sent in the last 7 days, vs the 7 before. Declined requests are gone.",
                        definition: `Friend requests sent in the last 7 days, up to now, compared with the 7 days before. ${kept}.`,
                        example: (r) => `People sent ${r.count(r.value, "friend request", "friend requests")} in the last 7 days that are still pending or accepted${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select created_at as at from (${pairs}) as pair`, count),
                    },
                    {
                        id: "acceptance_rate", title: "Monthly acceptance rate", unit: "percent", better: true,
                        note: "Share of the last 30 days' requests accepted now, vs the 30 before. Reads high.",
                        definition: `Of the friend requests sent in the last 30 days, up to now, the share accepted now, compared with the 30 days before. ${kept}, so the rate reads high. Recent requests have had less time to be accepted.`,
                        example: (r) => `${r.format(r.value)} of the friend requests sent in the last 30 days are accepted${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`select created_at as at, state from (${pairs}) as pair`,
                            sql`avg(case when e.state = 'accepted' then 100.0 else 0 end)`),
                    },
                    {
                        id: "time_to_accept", title: "Monthly median time to accept", unit: "hours", better: false,
                        note: "Requests accepted in the last 30 days, vs the 30 before.",
                        definition: "The median time from a friend request to its acceptance, for the requests accepted in the last 30 days, up to now, compared with the 30 days before. Half were accepted faster. Friendships removed since are not counted.",
                        example: (r) => `Half of the friend requests accepted in the last 30 days were accepted within ${r.format(r.value)}${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select accepted_at as at, extract(epoch from accepted_at - created_at) / 3600 as waited
                            from (${friendships}) as pair
                        `, sql`percentile_cont(0.5) within group (order by e.waited)`),
                    },
                    {
                        id: "pending_requests", title: "Pending friend requests", unit: "count", better: null,
                        note: "Waiting for an answer now, vs 7 days ago.",
                        definition: "Friend requests waiting for an answer now, compared with 7 days ago. Declining a request deletes it, so 7 days ago only counts requests that were later accepted or are still pending.",
                        example: (r) => `${r.count(r.value, "friend request is", "friend requests are")} waiting for an answer now${r.against("a week ago")}.`,
                        query: sql`
                            select count(*) filter (where state = 'pending')::float8 as value,
                                count(*) filter (
                                    where created_at < ${ago(7)} and (accepted_at is null or accepted_at >= ${ago(7)})
                                )::float8 as previous
                            from (${pairs}) as pair
                        `,
                    },
                    {
                        id: "live_friend_fights", title: "Live friend fights", unit: "count", better: true,
                        note: "Now, vs 7 days ago.",
                        definition: "Monthly friend Fights running now, one per pair of friends, compared with 7 days ago. Every friendship gets one automatically. A friend Fight ended by removing the friend is cancelled and counts in neither number.",
                        example: (r) => `${r.count(r.value, "friend fight is", "friend fights are")} live now${r.against("a week ago")}.`,
                        query: sql`
                            select count(*) filter (where starts_at <= ${w.now} and ends_at > ${w.now})::float8 as value,
                                count(*) filter (where starts_at <= ${ago(7)} and ends_at > ${ago(7)})::float8 as previous
                            from public.fights as f where (to_jsonb(f) ->> 'friends') = 'true' and state not in ('draft', 'cancelled')
                        `,
                    },
                    {
                        id: "friend_fight_syncs", title: "Monthly friend fight sync", unit: "percent", better: true,
                        note: "Fighters with complete steps in friend Fights finished in the last 30 days, vs the 30 before.",
                        definition: "Of the fighters in friend Fights that ended with results in the last 30 days, up to now, the share whose steps were complete through the last day, compared with the 30 days before. Friend Fights all end at the end of the month, so a span usually holds one month's results.",
                        example: (r) => `${r.format(r.value)} of the fighters in friend fights that finished in the last 30 days had complete steps${r.against("for the 30 days before")}.`,
                        query: eventCard(sql, w, 30, sql`
                            select f.ends_at as at, m.final_steps_complete as complete
                            from public.fights as f
                            join public.fight_members as m on m.fight_id = f.id and m.state = 'accepted'
                            where (to_jsonb(f) ->> 'friends') = 'true' and f.state = 'final'
                        `, sql`avg(case when e.complete then 100.0 else 0 end)`),
                    },
                ],
                charts: [
                    {
                        id: "new_friendships_per_bucket", title: `New friendships ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Friend requests accepted in each ${w.bucket}. Friendships removed since are not counted.`,
                        example: (r) => {
                            const n = r.at();
                            return n === undefined ? null : `${r.count(n, "new friendship", "new friendships")} started ${r.when}.`;
                        },
                        query: perBucket(sql, w, sql`select accepted_at as at from (${friendships}) as pair`, count),
                    },
                    {
                        id: "requests_and_accepts", title: `Friend requests and accepts ${per}`, kind: "line", unit: "count", x: "date",
                        definition: `Friend requests sent, and friend requests accepted, in each ${w.bucket}. ${kept}.`,
                        example: (r) => {
                            const sent = r.at("Requests sent");
                            const accepted = r.at("Accepted");
                            return sent === undefined || accepted === undefined ? null
                                : `${r.count(sent, "friend request was", "friend requests were")} sent ${r.when}, and ${r.format(accepted)} accepted.`;
                        },
                        note: "Only requests still pending or accepted: declined ones are deleted.",
                        query: perBucket(sql, w, sql`
                            select created_at as at, 'Requests sent' as series from (${pairs}) as pair
                            union all
                            select accepted_at, 'Accepted' from (${friendships}) as pair
                        `, count, { series: ["Requests sent", "Accepted"] }),
                    },
                    {
                        id: "friends_per_user", title: "Friends per user, now", kind: "bar", unit: "count", x: "label",
                        definition: "Every user by their number of friends now. Deleted accounts and blocked pairs are not counted.",
                        example: (r) => {
                            const none = r.row("None");
                            return none === undefined || r.total === 0 ? null
                                : `${r.count(r.total - none, "user has", "users have")} at least one friend, out of ${r.format(r.total)}.`;
                        },
                        query: sql`
                            select band.x, count(c.user_id)::float8 as y from (values
                                (1, 'None', 0, 0), (2, '1', 1, 1), (3, '2', 2, 2), (4, '3-5', 3, 5), (5, '6-10', 6, 10),
                                (6, '11+', 11, 1000000)
                            ) as band(position, x, low, high)
                            left join (${friendCounts}) as c on c.friends between band.low and band.high
                            group by band.position, band.x order by band.position
                        `,
                    },
                    {
                        id: "friendships_over_time", title: "Total friendships", kind: "line", unit: "count", x: "date",
                        definition: `Pairs of friends at the end of each ${w.bucket}, and now for the last point. Removing a friend deletes the pair, so earlier points only count pairs that are still friends.`,
                        example: (r) => {
                            const now = r.latest();
                            const start = r.first();
                            return now === undefined || !start ? null
                                : `FitFight has ${r.count(now, "pair of friends", "pairs of friends")} now, against ${r.format(start.y)} at the end of ${r.period(start.x)}.`;
                        },
                        note: `At the end of each ${w.bucket}, now for the last one.`,
                        query: sql`
                            select point.bucket::text as x, count(pair.user_low)::float8 as y
                            from (${samplePoints(sql, w)}) as point
                            left join (${friendships}) as pair on (pair.accepted_at at time zone 'Europe/Paris')::date <= point.day
                            group by point.bucket order by point.bucket
                        `,
                    },
                ],
            };
        }
        case "app": {
            // NOTE: build 210 reports every HealthKit observer wake, and most only join a sync already
            // running and record no stage. A Steps sync reads Steps (local_state or today_total); the
            // other-activity import and Fights-only refreshes are separate traces with their own rows.
            const attempts = sql`
                select user_id, started_at as at, trigger, outcome, error_code, total_ms, app_version, app_build,
                    case
                        when stages @> '[{"stage":"today_total"}]' or stages @> '[{"stage":"local_state"}]' then 'steps'
                        when stages @> '[{"stage":"healthkit_activity"}]' then 'activity'
                    end as work
                from private.healthkit_sync_attempts
            `;
            const syncs = sql`select * from (${attempts}) as a where a.work = 'steps'`;
            // NOTE: total_ms is wall-clock time, so it includes iOS pausing the app mid-sync. Syncs over 2
            // minutes (1-3% of completed Steps syncs a day, some genuinely slow) are left out of timing only.
            const timed = sql`select * from (${syncs}) as s where s.outcome <> 'cancelled' and s.total_ms <= 120000`;
            const errors = sql`select user_id, created_at as at, action, status from private.server_error_logs`;
            const sent = sql`
                select user_id, coalesce(processed_at, created_at) as at, kind
                from private.notification_intents where status = 'sent'
            `;
            return {
                cards: [
                    {
                        id: "health_share", title: "Weekly share syncing Health", unit: "percent", better: true,
                        note: "Share of users whose phone synced Apple Health in the last 7 days, vs the 7 before.",
                        definition: "The share of all users whose phone synced Apple Health at least once in the last 7 days, compared with the 7 days before, out of the users who had signed up by then. iOS does not tell FitFight when someone turns Health off or deletes the app, so a phone that stops syncing is how a lost connection shows.",
                        example: (r) => `${r.format(r.value)} of users had their phone sync Apple Health in the last 7 days${r.against("in the 7 days before")}.`,
                        query: sql`
                            select 100.0 * (select count(distinct user_id) from (${syncs}) as s
                                    where s.outcome = 'succeeded' and s.at >= ${ago(7)} and s.at < ${w.now})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${w.now}), 0) as value,
                                100.0 * (select count(distinct user_id) from (${syncs}) as s
                                    where s.outcome = 'succeeded' and s.at >= ${ago(14)} and s.at < ${ago(7)})
                                    / nullif((select count(*) from public.profiles where deleted_at is null and created_at < ${ago(7)}), 0) as previous
                        `,
                    },
                    {
                        id: "sync_success", title: "Weekly sync success", unit: "percent", better: true,
                        note: "Share of Steps syncs that succeeded, last 7 days vs the 7 before.",
                        definition: "The share of Apple Health Steps syncs that succeeded in the last 7 days, up to now, compared with the 7 days before. Background syncs, app opens and manual refreshes all count. Wakes that only joined a sync already running, the separate other-activity import and Fights-only refreshes do not.",
                        example: (r) => `${r.format(r.value)} of Steps syncs succeeded in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, syncs, sql`avg(case when e.outcome = 'succeeded' then 100.0 else 0 end)`),
                    },
                    {
                        id: "background_syncs", title: "Weekly background syncs", unit: "count", better: true,
                        note: "Steps syncs Apple Health started without an open. Last 7 days vs the 7 before.",
                        definition: "Steps syncs that Apple Health started in the background, without an app open, in the last 7 days, up to now, compared with the 7 days before. A wake that only joined a sync already running is not a sync.",
                        example: (r) => `Apple Health started ${r.count(r.value, "background Steps sync", "background Steps syncs")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select * from (${syncs}) as a where a.trigger = 'observer'`, count),
                    },
                    {
                        id: "sync_time", title: "Weekly median sync time", unit: "seconds", better: false,
                        note: "Last 7 days vs the 7 before. Syncs over 2 minutes left out.",
                        definition: "The median time an Apple Health Steps sync took in the last 7 days, up to now, compared with the 7 days before. Half of the syncs were faster. Cancelled syncs and syncs that ran over 2 minutes are left out: that time is iOS pausing the app, not the sync.",
                        example: (r) => `Half of the Steps syncs in the last 7 days took ${r.format(r.value)} or less${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, timed, sql`percentile_cont(0.5) within group (order by e.total_ms / 1000.0)`),
                    },
                    {
                        id: "push_share", title: "Registered for push", unit: "percent", better: true,
                        note: "Share of users with a registered device, now.",
                        definition: "The share of all users with at least one device registered for FitFight notifications, now. A phone registers only after its owner allows notifications, and the app does not report turning them off later in iOS Settings, so this is an upper bound. There is no comparison.",
                        example: (r) => `${r.format(r.value)} of users have a device registered for push notifications now.`,
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
                        definition: "Push notifications the server sent in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `The server sent ${r.count(r.value, "notification", "notifications")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sent, count),
                    },
                    {
                        id: "server_errors", title: "Weekly server errors", unit: "count", better: false,
                        note: "Last 7 days vs the 7 before.",
                        definition: "API requests the server logged as failing with a server error (HTTP 5xx) in the last 7 days, up to now, compared with the 7 days before.",
                        example: (r) => `The server logged ${r.count(r.value, "error", "errors")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, errors, count),
                    },
                    {
                        id: "latest_build_share", title: "Weekly newest-build share", unit: "percent", better: true,
                        note: "Active people in the last 7 days whose latest build is the newest seen.",
                        definition: "Of the people whose phone synced Apple Health in the last 7 days, the share whose latest sync came from the newest app build seen in that time. There is no comparison.",
                        example: (r) => `${r.format(r.value)} of the people whose phone synced in the last 7 days are on the newest build.`,
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
                        id: "sync_issue_users", title: "Steps sync failing now", unit: "count", better: false,
                        note: "People whose latest Steps sync failed.",
                        definition: "People whose latest Apple Health Steps sync failed, however long ago it ran. Failures of the separate other-activity import are in Sync errors by code. There is no comparison.",
                        example: (r) => `The latest Steps sync failed for ${r.count(r.value, "person", "people")}.`,
                        query: sql`
                            select (count(*) filter (where latest.outcome = 'failed'))::float8 as value, null::float8 as previous
                            from (select distinct on (user_id) user_id, outcome from (${syncs}) as s order by user_id, s.at desc) as latest
                        `,
                    },
                ],
                charts: [
                    {
                        id: "sync_outcomes", title: `Sync outcomes ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `Apple Health Steps syncs in each ${w.bucket}, by result. Wakes that only joined a sync already running, the separate other-activity import and Fights-only refreshes are not counted.`,
                        example: (r) => {
                            const ok = r.at("Succeeded") ?? 0;
                            const all = ok + (r.at("Failed") ?? 0) + (r.at("Cancelled") ?? 0);
                            const part = r.share(ok, all);
                            return part ? `${part} of Steps syncs succeeded ${r.when}: ${r.format(ok)} of ${r.format(all)}.` : null;
                        },
                        query: perBucket(sql, w, sql`select at, initcap(outcome) as series from (${syncs}) as a`, count, {
                            gaps: true, series: ["Succeeded", "Failed", "Cancelled"],
                        }),
                    },
                    {
                        id: "sync_triggers", title: `Syncs by trigger ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: "Why each Steps sync ran: Apple Health woke the app in the background, the app opened, or someone refreshed by hand (pull to refresh, or creating, editing or joining a Fight). Wakes that only joined a sync already running and syncs without a Steps read, such as the other-activity import and Fights-only refreshes, are not counted.",
                        example: (r) => {
                            const background = r.at("Background") ?? 0;
                            const all = background + (r.at("App opened") ?? 0) + (r.at("Manual") ?? 0);
                            const part = r.share(background, all);
                            return part ? `${part} of Steps syncs ran in the background ${r.when}: ${r.format(background)} of ${r.format(all)}.` : null;
                        },
                        query: perBucket(sql, w, sql`
                            select at, case trigger when 'foreground' then 'App opened' when 'observer' then 'Background'
                                else 'Manual' end as series
                            from (${syncs}) as a
                        `, count, { gaps: true, series: ["Background", "App opened", "Manual"] }),
                    },
                    {
                        id: "sync_durations", title: "Sync time: P10 to P99", kind: "line", unit: "seconds", x: "date",
                        definition: "How long a Steps sync takes. Each line is a percentile: P10 means 10% of syncs were faster, P50 is the typical sync, and P99 means only 1% were slower. Cancelled syncs and syncs that ran over 2 minutes are left out: that time is iOS pausing the app, not the sync.",
                        example: (r) => {
                            const fast = r.at("P10");
                            const typical = r.at("P50");
                            const slow = r.at("P99");
                            return fast === undefined || typical === undefined || slow === undefined ? null
                                : `A typical Steps sync took ${r.format(typical)} ${r.when}. The fastest 10% took ${r.format(fast)} or less, and the slowest 1% took ${r.format(slow)} or more.`;
                        },
                        note: `Across each ${w.bucket}'s Steps syncs.`,
                        query: sql`
                            with bucketed as (
                                select date_trunc(${w.bucket}::text, (at at time zone 'Europe/Paris')::date::timestamp)::date as bucket,
                                    percentile_cont(array[0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99])
                                        within group (order by total_ms / 1000.0) as times
                                from (${timed}) as a
                                where (a.at at time zone 'Europe/Paris')::date >= ${w.start}::date group by 1
                            )
                            select bucketed.bucket::text as x, value.y::float8 as y, value.series
                            from bucketed cross join lateral unnest(
                                bucketed.times, array['P10', 'P25', 'P50', 'P75', 'P90', 'P95', 'P99']
                            ) with ordinality as value(y, series, position)
                            order by value.position, bucketed.bucket
                        `,
                    },
                    {
                        id: "errors_per_bucket", title: `Server errors ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `API requests the server logged as failing with a server error (HTTP 5xx), in each ${w.bucket}.`,
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
                        example: (r) => (r.top && r.top.y > 0 ? `${r.count(r.top.y, "person uses", "people use")} ${r.top.x}: ${r.top.share} of people whose phone synced in the last 7 days.` : null),
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
                        definition: "Failed Apple Health syncs in the last 7 days, by error. Steps is the Steps sync; Other activity is the separate import of workouts and other activity. Cancelled syncs and Fights-only refreshes are not counted.",
                        example: (r) => (r.top && r.top.y > 0 ? `"${r.top.x}" is the most common sync error: ${r.count(r.top.y, "time", "times")} in 7 days.` : null),
                        query: sql`
                            select case a.work when 'steps' then 'Steps: ' else 'Other activity: ' end
                                || replace(error_code, '_', ' ') as x, count(*)::float8 as y
                            from (${attempts}) as a
                            where a.outcome = 'failed' and a.work is not null and a.error_code is not null
                                and a.at >= ${ago(7)} and a.at < ${w.now}
                            group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "errors_by_path", title: "Server errors by route, last 7 days", kind: "bar", unit: "count", x: "label",
                        definition: "Server errors (HTTP 5xx) in the last 7 days, by method and API route.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} failed the most: ${r.count(r.top.y, "error", "errors")} in 7 days.` : null),
                        query: sql`
                            select e.action as x, count(*)::float8 as y from (${errors}) as e
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
                        id: "push_permissions", title: "Registered push devices, now", kind: "bar", unit: "count", x: "label",
                        definition: "Devices registered for notifications, by permission, now. A device registers only after its owner allows notifications, and the app does not report turning them off later, so every device shows Authorized.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "device", "devices")}, ${r.top.share} of all.` : null),
                        query: sql`
                            select initcap(replace(coalesce(permission_status, 'unknown'), '_', ' ')) as x, count(*)::float8 as y
                            from private.device_installations where revoked_at is null group by 1 order by 2 desc
                        `,
                    },
                    {
                        id: "background_refresh", title: "Background App Refresh, now", kind: "bar", unit: "count", x: "label",
                        definition: "Accounts by the Background App Refresh setting their phone last reported, which background syncs need.",
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x}: ${r.count(r.top.y, "account", "accounts")}, ${r.top.share} of all.` : null),
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
        case "metrics": {
            // NOTE: Fights score each member's Apple Health Steps (fight_members.selected_source_id). Every
            // other source and metric is stored and listed here, and scores nothing.
            const scoring = "Fights score Steps from Apple Health. Other sources are collected only.";
            // A new provider also needs its name in the chart's series to get its own bars over time.
            const sourceName = sql`
                case source.provider when 'apple_health' then 'Apple Health' when 'whoop' then 'WHOOP' else source.provider end
            `;
            const raw = sql`
                select raw.user_id, raw.received_at as at, source.provider, ${sourceName} as series
                from private.activity_raw as raw
                join public.data_sources as source on source.id = raw.source_id
            `;
            return {
                cards: [
                    {
                        id: "whoop_connected", title: "WHOOP connected", unit: "count", better: true,
                        note: "People with a working WHOOP login, now. Collected only: Fights do not score WHOOP.",
                        definition: "People whose WHOOP login FitFight can use now. A login WHOOP stopped accepting does not count. WHOOP records are collected only: Fights do not score them. There is no comparison.",
                        example: (r) => `${r.count(r.value, "person has", "people have")} WHOOP connected now.`,
                        // NOTE: access_token_expires_at is set exactly when the sealed tokens are
                        // (whoop_connections_tokens), so the dashboard never reads the token columns.
                        query: sql`
                            select count(*) filter (where access_token_expires_at is not null)::float8 as value,
                                null::float8 as previous
                            from private.whoop_connections
                        `,
                    },
                    {
                        id: "apple_health_people", title: "Weekly people sending Apple Health", unit: "count", better: true,
                        note: "Sent new Apple Health records in the last 7 days, vs the 7 before.",
                        definition: `People whose phone sent at least one new Apple Health record in the last 7 days, up to now, compared with the 7 days before. Each person counts once. ${scoring}`,
                        example: (r) => `${r.count(r.value, "person's phone", "people's phones")} sent new Apple Health records in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, sql`select * from (${raw}) as raw where raw.provider = 'apple_health'`, people),
                    },
                    {
                        id: "raw_received", title: "Weekly raw records received", unit: "count", better: null,
                        note: "Every source, last 7 days vs the 7 before.",
                        definition: "New raw records FitFight stored from every source in the last 7 days, up to now, compared with the 7 days before. A record counts when it first arrives: the same content sent again does not count, and content that changed counts as a new record.",
                        example: (r) => `FitFight received ${r.count(r.value, "new raw record", "new raw records")} in the last 7 days${r.against("in the 7 days before")}.`,
                        query: eventCard(sql, w, 7, raw, count),
                    },
                    {
                        id: "raw_pending", title: "Raw records pending", unit: "count", better: null,
                        note: "Waiting to be cleaned into metrics, now.",
                        definition: "Raw records from every source still waiting to be cleaned into metrics, now. WHOOP records are collected only, so they stay pending. Records that failed to clean are not counted. There is no comparison.",
                        example: (r) => `${r.count(r.value, "raw record is", "raw records are")} waiting to be cleaned now.`,
                        query: sql`
                            select count(*)::float8 as value, null::float8 as previous
                            from private.activity_raw where processing_state = 'pending'
                        `,
                    },
                ],
                charts: [
                    {
                        id: "raw_by_type", title: "Raw records by source and type, all time", kind: "table", unit: "count", x: "label",
                        definition: `Every type of raw record FitFight has stored, by source: how many records, how many people sent them, and how many hours ago the newest arrived. ${scoring}`,
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} has the most raw records: ${r.format(r.top.y)}, ${r.top.share} of all.` : null),
                        note: scoring,
                        query: sql`
                            select grouped.x, cell.y, cell.series
                            from (
                                select ${sourceName} || ': ' || raw.record_type as x, count(*) as total,
                                    count(distinct raw.user_id) as people, max(raw.received_at) as newest
                                from private.activity_raw as raw
                                join public.data_sources as source on source.id = raw.source_id
                                group by 1
                            ) as grouped
                            cross join lateral (values
                                (1, 'Records', grouped.total::float8),
                                (2, 'People', grouped.people::float8),
                                (3, 'Hours since last', extract(epoch from ${w.now} - grouped.newest)::float8 / 3600)
                            ) as cell(position, series, y)
                            order by grouped.total desc, grouped.x, cell.position
                        `,
                    },
                    {
                        id: "metrics_by_source", title: "Cleaned metrics by source, all time", kind: "table", unit: "count", x: "label",
                        definition: `Every metric cleaned from raw records, by source: how many rows, how many people they belong to, and how many days ago the latest one was. The metric Fights score is marked. ${scoring}`,
                        example: (r) => (r.top && r.top.y > 0 ? `${r.top.x} has the most cleaned rows: ${r.format(r.top.y)}, ${r.top.share} of all.` : null),
                        note: scoring,
                        query: sql`
                            select grouped.x, cell.y, cell.series
                            from (
                                select ${sourceName} || ': ' || metric.metric || case
                                        when source.provider = 'apple_health' and metric.metric = 'steps' then ' (scores Fights)' else ''
                                    end as x,
                                    count(*) as total, count(distinct metric.user_id) as people,
                                    max(coalesce(metric.day, (metric.observed_through at time zone 'Europe/Paris')::date)) as latest
                                from private.activity_metrics as metric
                                join public.data_sources as source on source.id = metric.source_id
                                group by 1
                            ) as grouped
                            cross join lateral (values
                                (1, 'Rows', grouped.total::float8),
                                (2, 'People', grouped.people::float8),
                                (3, 'Days since latest', greatest(${w.today}::date - grouped.latest, 0)::float8)
                            ) as cell(position, series, y)
                            order by grouped.total desc, grouped.x, cell.position
                        `,
                    },
                    {
                        id: "raw_per_bucket", title: `Raw records ${per}`, kind: "bar", unit: "count", x: "date",
                        definition: `New raw records FitFight stored in each ${w.bucket}, by source. A record counts when it first arrives.`,
                        example: (r) => {
                            const apple = r.at("Apple Health");
                            const whoop = r.at("WHOOP");
                            return apple === undefined || whoop === undefined ? null
                                : `FitFight received ${r.count(apple, "new Apple Health record", "new Apple Health records")} and ${r.count(whoop, "new WHOOP record", "new WHOOP records")} ${r.when}.`;
                        },
                        query: perBucket(sql, w, raw, count, { series: ["Apple Health", "WHOOP"] }),
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
            const tile = {
                id: card.id, title: card.title, unit: card.unit, higher_is_better: card.better,
                definition: card.definition,
            };
            try {
                const row = adminDashboardCardRowSchema.parse((await card.query)[0]);
                const example = row.value === null ? null : card.example({
                    value: row.value,
                    format: (value, unit = card.unit) => readable(value, unit),
                    count: counted,
                    against: (when) => (row.previous === null ? "" : `, against ${readable(row.previous, card.unit)} ${when}`),
                });
                return { ...tile, ...row, note: card.note ?? null, example };
            } catch (error) {
                return { ...tile, value: null, previous: null, note: failure(error), example: null };
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

/**
 * The Users tab's table: the newest accounts first, `limit` of them from `offset`, each column by
 * the dashboard's own rules. Deleted accounts are left out.
 */
export async function readAdminUsers(
    limit: number,
    offset: number,
    environment: AdminDashboardEnvironment,
    database: Sql = createDatabaseClient(),
): Promise<AdminUsers> {
    const sql = database;
    const { stepPeople, referrals, userContests, friendPairs } = peopleRules(sql);
    // NOTE: production has private.account_auth, the only way its read-only user reads emails, once
    // 20261019120000_account_auth reaches `main`. Until then its emails and sign-in methods read null.
    const { total, accounts } = adminUsersCountRowSchema.parse((await sql`
        select count(*)::int as total, to_regclass('private.account_auth') is not null as accounts
        from public.profiles where deleted_at is null
    `)[0]);
    const users = await sql`
        with page as (
            select user_id, handle, handle_set_at, display_name, created_at, time_zone
            from public.profiles where deleted_at is null
            order by created_at desc, user_id limit ${limit} offset ${offset}
        ),
        friends as (
            select side.user_id, count(*)::int as friends
            from (
                select pair.user_low as user_id from (${friendPairs}) as pair where pair.state = 'accepted'
                union all select pair.user_high from (${friendPairs}) as pair where pair.state = 'accepted'
            ) as side
            group by side.user_id
        )
        select p.user_id, p.handle, p.handle_set_at is not null as handle_set, p.display_name,
            ${accounts ? sql`account.email, account.providers` : sql`null::text as email, null::text[] as providers`},
            to_char(p.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at,
            coalesce(friends.friends, 0) as friends,
            exists (
                select 1 from public.fight_series_members as member
                join public.fight_series as series on series.id = member.series_id
                where member.user_id = p.user_id and member.state = 'accepted' and series.join_code = 'PGG7'
            ) as everybody_fight,
            (select count(distinct f.series_id)::int from public.fight_members as m
                join (${userContests}) as f on f.id = m.fight_id
                where m.user_id = p.user_id and m.state = 'accepted' and m.user_id::text is distinct from f.host) as fights,
            (select referrer.handle from (${referrals}) as r
                join public.profiles as referrer on referrer.user_id = r.user_id
                where r.referred_user_id = p.user_id) as referred_by,
            (select count(*)::int from (${referrals}) as r where r.user_id = p.user_id) as referrals,
            p.user_id in (${stepPeople}) as health_connected,
            (select to_char(max(source.last_success_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                from public.data_sources as source
                where source.user_id = p.user_id and source.provider = 'apple_health') as last_synced_at,
            (select attempt.app_version || ' (' || attempt.app_build || ')' from private.healthkit_sync_attempts as attempt
                where attempt.user_id = p.user_id order by attempt.received_at desc limit 1) as app_version,
            exists (
                select 1 from private.device_installations as device
                where device.user_id = p.user_id and device.revoked_at is null
                    and device.permission_status in ('authorized', 'provisional', 'ephemeral')
            ) as notifications,
            p.time_zone
        from page as p
        left join friends on friends.user_id = p.user_id
        ${accounts ? sql`left join private.account_auth as account on account.user_id = p.user_id` : sql``}
        order by p.created_at desc, p.user_id
    `;
    return adminUsersSchema.parse({
        environment,
        total,
        users,
        note: accounts ? null : "Emails and sign-in methods show here once this database has the 19 Oct 2026 migration.",
    });
}
