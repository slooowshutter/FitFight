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
        for (const days of [1, 30, 3650]) {
            const dashboard = await readAdminDashboard(section, days, database);
            const failed = [...dashboard.cards, ...dashboard.charts]
                .filter((tile) => tile.note?.startsWith("Query failed"))
                .map((tile) => `${tile.id}: ${tile.note}`);
            assert.deepEqual(failed, [], `${section} over ${days} days`);
            assert.ok(dashboard.cards.length > 0 && dashboard.charts.length > 0);
        }
    }
    const engagement = await readAdminDashboard("engagement", 30, database);
    const opens = engagement.cards.find((card) => card.id === "app_opens");
    // Thirteen days of two foreground traces each; the one 20 seconds after a background sync is not an open.
    assert.ok(opens?.value !== undefined && opens.value !== null && opens.value >= 13);
});
