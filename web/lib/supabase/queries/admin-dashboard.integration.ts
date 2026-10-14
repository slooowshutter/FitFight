import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { adminDashboardSectionValues } from "@/lib/types/admin/admin-dashboard";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readAdminDashboard } from "./admin-dashboard-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

test("every admin dashboard card and chart runs on the migrated schema", async (t) => {
    const userId = randomUUID();
    const sourceId = randomUUID();
    const fightId = randomUUID();
    const stoppedId = randomUUID();
    const stoppedSourceId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id in (${userId}, ${stoppedId})`;
    });
    await database`insert into auth.users(id, created_at) values (${userId}, now() - interval '20 days')`;
    await database`
        update public.profiles set handle = ${`dash_${userId.slice(0, 8)}`}, handle_set_at = now() - interval '20 days',
            time_zone = 'Europe/Paris', created_at = now() - interval '20 days'
        where user_id = ${userId}
    `;
    await database`
        insert into public.data_sources(id, user_id, provider, source_label, connection_route, capabilities, status,
            connected_at, last_success_at)
        values (${sourceId}, ${userId}, 'apple_health', 'Apple Health', 'healthkit', array['steps'], 'healthy',
            now() - interval '20 days', now() - interval '1 hour')
    `;
    await database`
        insert into private.activity_metrics(user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, time_zone, value, unit, input_ids, calculation_version)
        select ${userId}, ${sourceId}, 'day', 'day:' || day::date, 'steps', day, day + interval '1 day',
            day + interval '1 day', day::date, 'Europe/Paris', 6000 + extract(day from day) * 100, 'count',
            array[gen_random_uuid()], 1
        from generate_series(current_date - 40, current_date - 1, interval '1 day') as day
    `;
    await database`
        insert into private.healthkit_sync_attempts(user_id, attempt_id, trigger, started_at, outcome, total_ms,
            stages, app_version, app_build)
        select ${userId}, gen_random_uuid(), trigger, now() - make_interval(days => offset_days, secs => seconds),
            'succeeded', 1200, '[]'::jsonb, '1.1.3', '220'
        from generate_series(0, 12) as offset_days
        cross join (values ('observer', 30), ('foreground', 10), ('foreground', 7200), ('manual', 7000))
            as traced(trigger, seconds)
    `;
    await database`
        insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${userId}, 'Dashboard', 'live', now() - interval '2 days', now() + interval '5 days',
            'Europe/Paris', 'highest_total', 'shared')
    `;
    await database`insert into public.fight_members(fight_id, user_id, state, accepted_at) values (${fightId}, ${userId}, 'accepted', now())`;
    // A second phone synced steps from 30 to 10 days ago, then stopped.
    await database`insert into auth.users(id, created_at) values (${stoppedId}, now() - interval '30 days')`;
    await database`update public.profiles set created_at = now() - interval '30 days' where user_id = ${stoppedId}`;
    await database`
        insert into public.data_sources(id, user_id, provider, source_label, connection_route, capabilities, status,
            connected_at, last_success_at)
        values (${stoppedSourceId}, ${stoppedId}, 'apple_health', 'Apple Health', 'healthkit', array['steps'], 'healthy',
            now() - interval '30 days', now() - interval '10 days')
    `;
    await database`
        insert into private.activity_metrics(user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, time_zone, value, unit, input_ids, calculation_version)
        select ${stoppedId}, ${stoppedSourceId}, 'day', 'day:' || day::date, 'steps', day, day + interval '1 day',
            day + interval '1 day', day::date, 'Europe/Paris', 4000, 'count', array[gen_random_uuid()], 1
        from generate_series(current_date - 29, current_date - 10, interval '1 day') as day
    `;

    for (const section of adminDashboardSectionValues) {
        const cardValues: string[] = [];
        for (const days of [1, 30, 3650]) {
            const dashboard = await readAdminDashboard(section, days, "staging", database);
            const failed = [...dashboard.cards, ...dashboard.charts]
                .filter((tile) => tile.note?.startsWith("Query failed"))
                .map((tile) => `${tile.id}: ${tile.note}`);
            assert.deepEqual(failed, [], `${section} over ${days} days`);
            assert.ok(dashboard.cards.length > 0 && dashboard.charts.length > 0);
            assert.ok(
                [...dashboard.cards, ...dashboard.charts].every((tile) => /(^| )Took \d+(\.\d)? s\.$/.test(tile.note ?? "")),
                "Every tile reports its own query time",
            );
            assert.equal(dashboard.environment, "staging");
            assert.ok(
                dashboard.charts.every((chart) => chart.definition && !/undefined|NaN/.test(chart.example ?? "")),
                `${section} charts explain themselves`,
            );
            assert.ok(
                dashboard.cards.every((card) => card.definition && (card.value === null) === (card.example === null)
                    && !/undefined|NaN/.test(card.example ?? "")),
                `${section} cards explain themselves`,
            );
            cardValues.push(JSON.stringify(dashboard.cards.map(({ id, value, previous }) => [id, value, previous])));
        }
        assert.equal(new Set(cardValues).size, 1, `${section} cards have fixed spans, whatever the period`);
    }
    const engagement = await readAdminDashboard("engagement", 30, "staging", database);
    const opens = engagement.cards.find((card) => card.id === "app_opens");
    // Seven days of two foreground traces each; the one 20 seconds after a background sync is not an open.
    assert.ok(opens?.value !== undefined && opens.value !== null && opens.value >= 7);
    assert.match(opens.example ?? "", /^The app was opened \d+ times in the last 7 days, against \d+ in the 7 days before\.$/);
    const syncChurn = (await readAdminDashboard("churn", 30, "staging", database)).cards
        .find((card) => card.id === "weekly_sync_churn");
    assert.ok(syncChurn?.value, "The phone that stopped syncing counts as lost");
    assert.match(syncChurn.example ?? "", /^\d+(\.\d)?% of the people whose phone synced steps 8 to 14 days ago synced none in the last 7 days/);
    const syncTimes = (await readAdminDashboard("app", 30, "staging", database)).charts.find((chart) => chart.id === "sync_durations");
    assert.deepEqual(syncTimes?.series.map((line) => line.name), ["P10", "P25", "P50", "P75", "P90", "P95", "P99"]);

    const [first] = await database`
        select (min(created_at) at time zone 'Europe/Paris')::date::text as day from public.profiles
    `;
    const newUsers = async (days: number) => (await readAdminDashboard("overview", days, "staging", database))
        .charts.find((chart) => chart.id === "new_users_per_bucket")?.series[0]?.points ?? [];
    assert.equal((await newUsers(7)).length, 7, "Seven daily points for 7 days");
    assert.equal((await newUsers(3650))[0]?.x, first?.day, "A long period starts at the first signup, not years before it");

    const weekly = await readAdminDashboard("overview", 30, "staging", database, "week");
    assert.equal(weekly.bucket, "week");
    const weeks = weekly.charts.find((chart) => chart.id === "new_users_per_bucket")?.series[0]?.points ?? [];
    assert.ok(weeks.length >= 3 && weeks.every((point) => new Date(`${point.x}T00:00:00Z`).getUTCDay() === 1), "A chosen week bucket starts on Mondays");
    assert.equal((await readAdminDashboard("overview", 365, "staging", database, "day")).bucket, "day");
});

test("founder fights stay out of the fight, signup, fight-day and social metrics", async (t) => {
    const users = [randomUUID(), randomUUID()];
    const [founder, challenger] = users;
    const sourceId = randomUUID(), seriesId = randomUUID(), previousId = randomUUID(), fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id in (${previousId}, ${fightId})`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const id of users) await database`insert into auth.users(id, created_at) values (${id}, now() - interval '20 days')`;
    await database`update public.profiles set created_at = now() - interval '20 days' where user_id in ${database(users)}`;
    await database`
        insert into public.data_sources(id, user_id, provider, source_label, connection_route, capabilities, status,
            connected_at, last_success_at)
        values (${sourceId}, ${challenger}, 'apple_health', 'Apple Health', 'healthkit', array['steps'], 'healthy',
            now() - interval '20 days', now() - interval '1 hour')
    `;
    await database`
        insert into private.activity_metrics(user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, time_zone, value, unit, input_ids, calculation_version)
        select ${challenger}, ${sourceId}, 'day', 'day:' || day::date, 'steps', day, day + interval '1 day',
            day + interval '1 day', day::date, 'Europe/Paris', 4000 + extract(day from day) * 300, 'count',
            array[gen_random_uuid()], 1
        from generate_series(current_date - 20, current_date - 1, interval '1 day') as day
    `;
    const cardIds = ["fight_rate", "days_to_first_fight", "fight_day_lift", "fights_started", "joins", "fighters_per_fight",
        "cancel_rate", "recurring_share", "live_fights", "people_in_fights", "rounds_finished", "winning_margin"];
    const chartIds = ["fight_vs_other_days", "live_fights_over_time", "people_in_fights_over_time",
        "rounds_finished_per_bucket", "margins", "posts_by_fight"];
    const read = async () => {
        const dashboards = await Promise.all((["users", "steps", "fights", "social"] as const)
            .map((section) => readAdminDashboard(section, 30, "staging", database)));
        const cards = dashboards.flatMap((dashboard) => dashboard.cards);
        const charts = dashboards.flatMap((dashboard) => dashboard.charts);
        return [
            ...cardIds.map((id) => {
                const card = cards.find((item) => item.id === id);
                assert.ok(card, id);
                return [id, card.value, card.previous];
            }),
            ...chartIds.map((id) => {
                const chart = charts.find((item) => item.id === id);
                assert.ok(chart, id);
                return [id, chart.series];
            }),
        ];
    };
    const before = await read();
    await database`
        insert into public.fight_series (id, owner_id, host_id, name, visibility, recurring, duration_seconds, time_zone, join_code)
        values (${seriesId}, ${challenger}, ${founder}, 'Fight Marc', 'invite_only', true, 2592000, 'UTC', ${randomJoinCode()})
    `;
    await database`
        insert into public.fights (id, owner_id, host_id, name, series_id, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values
            (${previousId}, ${challenger}, ${founder}, 'Fight Marc', ${seriesId}, 'live', now() - interval '32 days',
                now() - interval '2 days', 'UTC', 'highest_total', 'shared'),
            (${fightId}, ${challenger}, ${founder}, 'Fight Marc', ${seriesId}, 'live', now() - interval '2 days',
                now() + interval '28 days', 'UTC', 'highest_total', 'shared')
    `;
    await database`insert into public.fight_members (fight_id, user_id, state, accepted_at) values
        (${previousId}, ${challenger}, 'accepted', now()), (${previousId}, ${founder}, 'accepted', now()),
        (${fightId}, ${challenger}, 'accepted', now()), (${fightId}, ${founder}, 'accepted', now())`;
    await database`update public.fight_members set current_value = case when user_id = ${challenger} then 1000 else 500 end,
        final_value = case when user_id = ${challenger} then 1000 else 500 end,
        rank = case when user_id = ${challenger} then 1 else 2 end, final_steps_complete = true where fight_id = ${previousId}`;
    await database`update public.fights set state = 'final' where id = ${previousId}`;
    await database`insert into public.fight_posts (fight_id, audience, author_id, body) values (${fightId}, 'fight', ${challenger}, 'Round two')`;
    assert.deepEqual(await read(), before);
});
