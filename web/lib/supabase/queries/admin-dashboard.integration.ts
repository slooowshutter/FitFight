import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
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
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id = ${userId}`;
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
            cardValues.push(JSON.stringify(dashboard.cards.map(({ id, value, previous }) => [id, value, previous])));
        }
        assert.equal(new Set(cardValues).size, 1, `${section} cards have fixed spans, whatever the period`);
    }
    const engagement = await readAdminDashboard("engagement", 30, "staging", database);
    const opens = engagement.cards.find((card) => card.id === "app_opens");
    // Seven days of two foreground traces each; the one 20 seconds after a background sync is not an open.
    assert.ok(opens?.value !== undefined && opens.value !== null && opens.value >= 7);

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

    // A launch reads today's steps first, so it is an open even 20 seconds after a background
    // sync. The upload of other activity and the Fights refreshes after an action are not opens.
    const weeklyOpens = async () => (await readAdminDashboard("engagement", 30, "staging", database))
        .cards.find((card) => card.id === "app_opens")?.value ?? 0;
    const opensBefore = await weeklyOpens();
    await database`
        insert into private.healthkit_sync_attempts(user_id, attempt_id, trigger, started_at, outcome, total_ms,
            stages, app_version, app_build)
        select ${userId}, gen_random_uuid(), traced.trigger,
            now() - make_interval(days => offset_days, hours => 3) + make_interval(secs => traced.seconds),
            'succeeded', 1200, traced.stages::jsonb, '1.1.3', '220'
        from generate_series(1, 5) as offset_days
        cross join (values
            ('observer', 0, '[{"stage": "upload"}]'),
            ('foreground', 20, '[{"stage": "today_total"}, {"stage": "upload"}, {"stage": "fights_refresh"}]'),
            ('foreground', 40, '[{"stage": "healthkit_activity"}, {"stage": "activity_upload"}]'),
            ('foreground', 180, '[{"stage": "session"}, {"stage": "fights_refresh"}]'),
            ('foreground', 360, '[{"stage": "session"}, {"stage": "fights_refresh"}]')
        ) as traced(trigger, seconds, stages)
    `;
    const addedOpens = (await weeklyOpens()) - opensBefore;
    assert.ok(Math.abs(addedOpens - 5) <= 1, `Five launches and no refreshes or uploads are opens, got ${addedOpens}`);

    // Complete sync history starts on one day: WAU needs 7 days of it, MAU 30, and a card window
    // that starts before it has no number.
    const byDay = await readAdminDashboard("engagement", 3650, "staging", database, "day");
    const line = (name: string) => byDay.charts.find((chart) => chart.id === "dau_wau_mau")
        ?.series.find((series) => series.name === name)?.points ?? [];
    const historyStart = line("DAU")[0]?.x;
    if (historyStart && first?.day && historyStart > first.day) {
        const historyMs = Date.parse(`${historyStart}T00:00:00Z`);
        const shifted = (days: number) => new Date(historyMs + days * 86_400_000).toISOString().slice(0, 10);
        assert.equal(line("WAU")[0]?.x, shifted(6), "WAU starts once sync history covers 7 days");
        assert.ok(line("MAU").length === 0 || line("MAU")[0]?.x === shifted(29), "MAU starts once sync history covers 30 days");
        const monthly = byDay.cards.find((card) => card.id === "monthly_active");
        if (Date.now() - 31 * 86_400_000 < historyMs) assert.equal(monthly?.value, null, "No monthly number before 30 days of history");
        if (Date.now() - 61 * 86_400_000 < historyMs) assert.equal(monthly?.previous, null, "No monthly change before 60 days of history");
    }

    // Cancelling a Fight keeps its members accepted, but they did not join a fight.
    const joinedFight = async () => (await readAdminDashboard("users", 30, "staging", database))
        .charts.find((chart) => chart.id === "funnel_all")?.series[0]?.points.find((point) => point.x === "Joined a fight")?.y ?? 0;
    const joinedBefore = await joinedFight();
    await database`update public.fights set state = 'cancelled' where id = ${fightId}`;
    assert.equal(await joinedFight(), joinedBefore - 1, "A member of a cancelled fight has not joined a fight");
});
