import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { adminDashboardSectionValues } from "@/lib/types/admin/admin-dashboard";
import type { AdminUser } from "@/lib/types/admin/admin-users";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readAdminDashboard, readAdminTablePage, readAdminUsers } from "./admin-dashboard-supabase-query";

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
            'succeeded', 1200, stages::jsonb, '1.1.3', '220'
        from generate_series(0, 12) as offset_days
        cross join (values
            ('observer', 30, '[{"stage": "local_state"}]'),
            ('observer', 29, '[]'),
            ('foreground', 10, '[{"stage": "fights_refresh"}]'),
            ('foreground', 7200, '[{"stage": "today_total"}]'),
            ('foreground', 7199, '[{"stage": "healthkit_activity"}]'),
            ('manual', 7000, '[{"stage": "today_total"}]'),
            ('foreground', 5000, '[{"stage": "today_total", "error": {"kind": "healthkit", "code": 6}}]'),
            ('foreground', 1400, '[{"stage": "today_total"}]')
        ) as traced(trigger, seconds, stages)
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
            const failed = [...dashboard.cards, ...dashboard.charts, ...dashboard.tables]
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
    assert.ok(opens?.value !== undefined && opens.value !== null && opens.value >= 7);
    assert.match(opens.example ?? "", /^The app was opened \d+ times in the last 7 days(, against \d+ in the 7 days before)?\.$/);
    // One open a day: the refresh 20 seconds after a background sync, the activity import, the locked
    // phone and the relaunch an hour after the last Health sync are not opens.
    const openers = engagement.charts.find((chart) => chart.id === "top_openers")?.series[0]?.points ?? [];
    assert.equal(openers.find((point) => point.x === `@dash_${userId.slice(0, 8)}`)?.y, 13);
    const syncChurn = (await readAdminDashboard("churn", 30, "staging", database)).cards
        .find((card) => card.id === "weekly_sync_churn");
    assert.ok(syncChurn?.value, "The phone that stopped syncing counts as lost");
    assert.match(syncChurn.example ?? "", /^\d+(\.\d)?% of the people whose phone synced steps 8 to 14 days ago synced none in the last 7 days/);
    const app = await readAdminDashboard("app", 30, "staging", database);
    const syncTimes = app.charts.find((chart) => chart.id === "sync_durations");
    assert.deepEqual(syncTimes?.series.map((line) => line.name), ["P10", "P25", "P50", "P75", "P90", "P95", "P99"]);
    // Seven days of one Steps sync and one empty wake each; the wake read nothing.
    assert.equal(app.cards.find((card) => card.id === "background_syncs")?.value, 7, "An observer wake with no stages is not a background sync");

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

/** The fight, signup, fight-day and social tiles that automatic rounds must not move. */
async function readFightMetrics() {
    const cardIds = ["fight_rate", "days_to_first_fight", "fight_day_lift", "fights_started", "joins", "fighters_per_fight",
        "cancel_rate", "recurring_share", "live_fights", "people_in_fights", "rounds_finished", "winning_margin"];
    const chartIds = ["fight_vs_other_days", "live_fights_over_time", "people_in_fights_over_time",
        "rounds_finished_per_bucket", "margins", "posts_by_fight"];
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
}

test("founder fights stay out of fight and social metrics but count for the challenger", async (t) => {
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
    const cardIds = ["fights_started", "joins", "fighters_per_fight", "cancel_rate", "recurring_share", "live_fights",
        "rounds_finished", "winning_margin"];
    const chartIds = ["live_fights_over_time", "rounds_finished_per_bucket", "margins", "posts_by_fight"];
    const read = async () => {
        const dashboards = await Promise.all((["users", "fights", "social"] as const)
            .map((section) => readAdminDashboard(section, 30, "staging", database)));
        const cards = dashboards.flatMap((dashboard) => dashboard.cards);
        const charts = dashboards.flatMap((dashboard) => dashboard.charts);
        const value = (id: string) => {
            const card = cards.find((item) => item.id === id);
            assert.ok(card, id);
            assert.ok(card.value !== null, id);
            return card.value;
        };
        return {
            joined: value("fight_rate"),
            live: value("people_in_fights"),
            unchanged: [
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
            ],
        };
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
    const [people] = await database<{ signups: number; users: number }[]>`
        select count(*) filter (where created_at >= now() - interval '30 days')::int as signups, count(*)::int as users
        from public.profiles where deleted_at is null
    `;
    const after = await read();
    assert.deepEqual(after.unchanged, before.unchanged);
    // The challenger joined a real Fight and is in it now; the founder, who is in every founder Fight, is not counted.
    assert.ok(people && Math.abs(after.joined - before.joined - 100 / people.signups) < 1e-9, "fight_rate counts the challenger only");
    assert.ok(people && Math.abs(after.live - before.live - 100 / people.users) < 1e-9, "people_in_fights counts the challenger only");
});

test("friend fights stay out of the fight metrics, and the friends section reads friendships", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    const [ada, ben, cleo, dan] = users;
    const seriesId = randomUUID(), previousId = randomUUID(), fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id in (${previousId}, ${fightId})`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    const readFriends = async () => {
        const dashboard = await readAdminDashboard("friends", 30, "staging", database);
        const card = (id: string) => {
            const found = dashboard.cards.find((item) => item.id === id);
            assert.ok(found, id);
            return found;
        };
        const points = (id: string, series?: string) => {
            const chart = dashboard.charts.find((item) => item.id === id);
            assert.ok(chart, id);
            return (series ? chart.series.find((line) => line.name === series) : chart.series[0])?.points ?? [];
        };
        const sum = (id: string, series?: string) => points(id, series).reduce((total, point) => total + point.y, 0);
        return { card, points, sum };
    };
    const [{ profiles }] = await database<{ profiles: number }[]>`
        select count(*)::int as profiles from public.profiles where deleted_at is null
    `;
    const before = await readFriends();

    for (const id of users) await database`insert into auth.users(id, created_at) values (${id}, now() - interval '20 days')`;
    await database`update public.profiles set created_at = now() - interval '20 days' where user_id in ${database(users)}`;
    // Ada and Ben became friends 10 days ago, Ada and Cleo 3 days ago; Dan's request to Cleo is
    // pending. Dan blocked Ben in Feed, so their friendship is not counted.
    await database`
        insert into private.profile_friendships(user_low, user_high, requester_id, state, created_at, accepted_at)
        values
            (least(${ada}::uuid, ${ben}::uuid), greatest(${ada}::uuid, ${ben}::uuid), ${ben}, 'accepted',
                now() - interval '10 days', now() - interval '10 days' + interval '2 hours'),
            (least(${ada}::uuid, ${cleo}::uuid), greatest(${ada}::uuid, ${cleo}::uuid), ${ada}, 'accepted',
                now() - interval '3 days', now() - interval '3 days' + interval '6 hours'),
            (least(${cleo}::uuid, ${dan}::uuid), greatest(${cleo}::uuid, ${dan}::uuid), ${dan}, 'pending',
                now() - interval '1 day', null),
            (least(${ben}::uuid, ${dan}::uuid), greatest(${ben}::uuid, ${dan}::uuid), ${ben}, 'accepted',
                now() - interval '5 days', now() - interval '5 days')
    `;
    await database`insert into private.feed_blocks(blocker_id, blocked_id) values (${dan}, ${ben})`;

    const fightMetrics = await readFightMetrics();
    await database`
        insert into public.fight_series (id, owner_id, name, visibility, recurring, duration_seconds, time_zone, join_code,
            friend_low, friend_high)
        values (${seriesId}, ${ben}, 'Friends', 'invite_only', true, 2592000, 'UTC', ${randomJoinCode()},
            least(${ada}::uuid, ${ben}::uuid), greatest(${ada}::uuid, ${ben}::uuid))
    `;
    await database`
        insert into public.fights (id, owner_id, name, series_id, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, friends)
        values
            (${previousId}, ${ben}, 'Friends', ${seriesId}, 'live', now() - interval '32 days', now() - interval '2 days',
                'UTC', 'highest_total', 'shared', true),
            (${fightId}, ${ben}, 'Friends', ${seriesId}, 'live', now() - interval '2 days', now() + interval '28 days',
                'UTC', 'highest_total', 'shared', true)
    `;
    await database`insert into public.fight_members (fight_id, user_id, state, accepted_at) values
        (${previousId}, ${ada}, 'accepted', now()), (${previousId}, ${ben}, 'accepted', now()),
        (${fightId}, ${ada}, 'accepted', now()), (${fightId}, ${ben}, 'accepted', now())`;
    await database`update public.fight_members set current_value = case when user_id = ${ada} then 1000 else 500 end,
        final_value = case when user_id = ${ada} then 1000 else 500 end,
        rank = case when user_id = ${ada} then 1 else 2 end, final_steps_complete = (user_id = ${ada}) where fight_id = ${previousId}`;
    await database`update public.fights set state = 'final' where id = ${previousId}`;
    assert.deepEqual(await readFightMetrics(), fightMetrics, "Friend rounds do not count as fights");

    const after = await readFriends();
    const moved = (id: string) => {
        const [now, then] = [after.card(id), before.card(id)];
        return [(now.value ?? 0) - (then.value ?? 0), (now.previous ?? 0) - (then.previous ?? 0)];
    };
    assert.deepEqual(moved("friendships_total"), [2, 1]);
    assert.deepEqual(moved("new_friendships"), [1, 1]);
    assert.deepEqual(moved("requests_sent"), [2, 1]);
    assert.deepEqual(moved("pending_requests"), [1, 0]);
    assert.deepEqual(moved("live_friend_fights"), [1, 1]);
    const average = after.card("average_friends").value ?? 0;
    assert.ok(Math.abs(average - ((before.card("average_friends").value ?? 0) * profiles + 4) / (profiles + 4)) < 1e-9,
        "Ada has 2 friends, Ben and Cleo 1, Dan none");
    const share = after.card("with_friend").value ?? 0;
    assert.ok(Math.abs(share - ((before.card("with_friend").value ?? 0) * profiles + 300) / (profiles + 4)) < 1e-9);
    assert.ok((after.card("median_friends").value ?? 0) >= 1);
    for (const id of ["acceptance_rate", "friend_fight_syncs"]) {
        const value = after.card(id).value;
        assert.ok(value !== null && value >= 0 && value <= 100, id);
    }
    assert.ok((after.card("time_to_accept").value ?? 0) > 0);
    assert.match(after.card("friendships_total").example ?? "", /^FitFight has [\d,]+ pairs? of friends now, against [\d,]+ a week ago\.$/);
    const bands = before.points("friends_per_user");
    assert.deepEqual(after.points("friends_per_user").map((point, index) => point.y - (bands[index]?.y ?? 0)), [1, 2, 1, 0, 0, 0]);
    assert.equal(after.sum("new_friendships_per_bucket") - before.sum("new_friendships_per_bucket"), 2);
    assert.equal(after.sum("requests_and_accepts", "Requests sent") - before.sum("requests_and_accepts", "Requests sent"), 3);
    assert.equal(after.sum("requests_and_accepts", "Accepted") - before.sum("requests_and_accepts", "Accepted"), 2);
    assert.equal((after.points("friendships_over_time").at(-1)?.y ?? 0) - (before.points("friendships_over_time").at(-1)?.y ?? 0), 2);
});

test("the metrics section lists every source, counts WHOOP as collected only and marks what Fights score", async (t) => {
    const [userId, revokedId, appleId, whoopId] = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from auth.users where id in (${userId}, ${revokedId})`;
    });
    const read = async () => {
        const dashboard = await readAdminDashboard("metrics", 30, "staging", database);
        const card = (id: string) => dashboard.cards.find((item) => item.id === id)?.value ?? 0;
        const points = (chart: string, series: string) => dashboard.charts.find((item) => item.id === chart)
            ?.series.find((line) => line.name === series)?.points ?? [];
        const cell = (chart: string, series: string, x: string) => points(chart, series).find((point) => point.x === x)?.y ?? 0;
        return { card, points, cell };
    };
    const before = await read();
    for (const id of [userId, revokedId]) await database`insert into auth.users(id, created_at) values (${id}, now() - interval '20 days')`;
    await database`
        insert into public.data_sources(id, user_id, provider, source_label, connection_route)
        values (${appleId}, ${userId}, 'apple_health', 'Apple Health', 'healthkit'), (${whoopId}, ${userId}, 'whoop', 'WHOOP', 'oauth')
    `;
    await database`
        insert into private.activity_raw(user_id, source_id, record_kind, record_type, record_key, payload, payload_hash,
            collected_at, received_at, processing_state)
        select ${userId}, raw.source_id::uuid, raw.kind, raw.type, raw.key, '{}', repeat(raw.key, 64), now(),
            now() - interval '1 minute', raw.state
        from (values
            (${appleId}, 'total', 'steps', '1', 'processed'),
            (${whoopId}, 'sample', 'whoop_cycle', '2', 'pending'),
            (${whoopId}, 'sample', 'whoop_cycle', '3', 'pending'),
            (${whoopId}, 'sample', 'whoop_sleep', '4', 'pending')
        ) as raw(source_id, kind, type, key, state)
    `;
    await database`
        insert into private.activity_metrics(user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, time_zone, value, unit, input_ids, calculation_version)
        select ${userId}, ${appleId}, 'day', 'day:1', 'steps', day::timestamp at time zone 'Europe/Paris',
            (day + 1)::timestamp at time zone 'Europe/Paris', (day + 1)::timestamp at time zone 'Europe/Paris',
            day, 'Europe/Paris', 5000, 'count', array[gen_random_uuid()], 1
        from (select (now() at time zone 'Europe/Paris')::date - 1 as day) as yesterday
    `;
    // The second login was revoked by WHOOP: its tokens are gone.
    await database`
        insert into private.whoop_connections(user_id, tokens_ciphertext, tokens_iv, tokens_tag, access_token_expires_at, connected_at)
        values (${userId}, 'sealed', 'iv', 'tag', now() + interval '1 hour', now()), (${revokedId}, null, null, null, null, now())
    `;
    const after = await read();
    const moved = (id: string) => after.card(id) - before.card(id);
    assert.deepEqual(
        ["whoop_connected", "apple_health_people", "raw_received", "raw_pending"].map(moved),
        [1, 1, 4, 3],
    );
    const cycle = "WHOOP: whoop_cycle";
    assert.equal(after.cell("raw_by_type", "Records", cycle) - before.cell("raw_by_type", "Records", cycle), 2);
    assert.equal(after.cell("raw_by_type", "People", cycle) - before.cell("raw_by_type", "People", cycle), 1);
    assert.ok(after.cell("raw_by_type", "Hours since last", cycle) < 1);
    const scored = "Apple Health: steps (scores Fights)";
    assert.equal(after.cell("metrics_by_source", "Rows", scored) - before.cell("metrics_by_source", "Rows", scored), 1);
    assert.ok(after.cell("metrics_by_source", "Days since latest", scored) <= 1);
    const today = after.points("raw_per_bucket", "WHOOP").at(-1);
    assert.ok(today);
    assert.equal(today.y - before.cell("raw_per_bucket", "WHOOP", today.x), 3);
});

test("the users table lists the newest accounts first, a page at a time, by the dashboard's rules", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [ada, ben, cleo] = users;
    const sourceId = randomUUID(), seriesId = randomUUID(), fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from public.fight_series_members where user_id in ${database(users)}`;
        await database`delete from public.fight_series where owner_id in ${database(users)}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    const referrersBefore = (await readAdminDashboard("users", 30, "staging", database)).cards
        .find((card) => card.id === "monthly_referrers")?.value ?? 0;

    // Ada signed up 3 days ago with Apple and later linked Google, Ben 2 days ago with Ada's link,
    // and Cleo yesterday without an email or a username.
    await database`
        insert into auth.users(id, email, raw_app_meta_data, created_at) values
            (${ada}, 'ada@example.com', ${database.json({ provider: "apple", providers: ["apple", "google"] })}, now() - interval '3 days'),
            (${ben}, 'ben@example.com', ${database.json({ provider: "google", providers: ["google"] })}, now() - interval '2 days'),
            (${cleo}, null, null, now() - interval '1 day')
    `;
    await database`
        update public.profiles as p set created_at = u.created_at,
            handle = case when p.user_id = ${cleo} then p.handle else 'u_' || left(replace(p.user_id::text, '-', ''), 12) end,
            handle_set_at = case when p.user_id <> ${cleo} then u.created_at end,
            time_zone = case when p.user_id = ${ada} then 'Europe/Paris' end
        from auth.users as u where u.id = p.user_id and p.user_id in ${database(users)}
    `;
    await database`
        insert into private.referrals(referred_user_id, referrer_user_id, created_at)
        values (${ben}, ${ada}, now() - interval '2 days' + interval '1 hour')
    `;
    await database`
        insert into private.profile_friendships(user_low, user_high, requester_id, state, created_at, accepted_at)
        values (least(${ada}::uuid, ${ben}::uuid), greatest(${ada}::uuid, ${ben}::uuid), ${ada}, 'accepted',
            now() - interval '1 day', now() - interval '1 day')
    `;
    // Ben is in the Everybody fight; Cleo joined it and left.
    await database`
        insert into public.fight_series (owner_id, join_code, duration_seconds, name, time_zone)
        values (${ada}, 'PGG7', 2592000, 'Everybody', 'UTC')
        on conflict do nothing
    `;
    await database`
        insert into public.fight_series_members(series_id, user_id, state)
        select series.id, member.user_id, member.state::public.fight_member_state
        from public.fight_series as series
        cross join (values (${ben}::uuid, 'accepted'), (${cleo}::uuid, 'withdrawn')) as member(user_id, state)
        where series.join_code = 'PGG7'
    `;
    await database`
        insert into public.fight_series (id, owner_id, name, visibility, recurring, duration_seconds, time_zone, join_code)
        values (${seriesId}, ${ada}, 'Duel', 'invite_only', false, 604800, 'UTC', ${randomJoinCode()})
    `;
    await database`
        insert into public.fights (id, owner_id, name, series_id, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${ada}, 'Duel', ${seriesId}, 'live', now() - interval '1 day', now() + interval '6 days',
            'UTC', 'highest_total', 'shared')
    `;
    await database`insert into public.fight_members (fight_id, user_id, state, accepted_at) values
        (${fightId}, ${ada}, 'accepted', now()), (${fightId}, ${ben}, 'accepted', now())`;
    await database`
        insert into public.data_sources(id, user_id, provider, source_label, connection_route, capabilities, status,
            connected_at, last_success_at)
        values (${sourceId}, ${ben}, 'apple_health', 'Apple Health', 'healthkit', array['steps'], 'healthy',
            now() - interval '2 days', '2026-10-18T10:00:00Z')
    `;
    await database`
        insert into private.activity_metrics(user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, time_zone, value, unit, input_ids, calculation_version)
        values (${ben}, ${sourceId}, 'day', 'day:' || (current_date - 1), 'steps', current_date - 1, current_date,
            current_date, current_date - 1, 'Europe/Paris', 5000, 'count', array[gen_random_uuid()], 1)
    `;
    await database`
        insert into private.healthkit_sync_attempts(user_id, attempt_id, trigger, started_at, received_at, outcome,
            total_ms, stages, app_version, app_build)
        values
            (${ben}, gen_random_uuid(), 'foreground', now() - interval '1 day', now() - interval '1 day', 'succeeded',
                900, '[]', '1.1.3', '226'),
            (${ben}, gen_random_uuid(), 'foreground', now() - interval '1 hour', now() - interval '1 hour', 'succeeded',
                900, '[]', '1.2.1', '234')
    `;
    // Ada allowed notifications; Ben's phone was revoked.
    await database`
        insert into private.device_installations(user_id, token_fingerprint, encrypted_token, encryption_iv,
            encryption_tag, apns_environment, permission_status, revoked_at)
        values
            (${ada}, ${`fingerprint-${ada}`}, 'sealed', 'iv', 'tag', 'production', 'authorized', null),
            (${ben}, ${`fingerprint-${ben}`}, 'sealed', 'iv', 'tag', 'production', 'authorized', now())
    `;

    const all = await readAdminUsers(100, 0, "staging", database);
    const [{ total }] = await database<{ total: number }[]>`
        select count(*)::int as total from public.profiles where deleted_at is null
    `;
    assert.equal(all.total, total);
    assert.equal(all.environment, "staging");
    assert.equal(all.note, null);
    const mine = all.users.filter((user) => users.some((id) => id === user.user_id));
    assert.deepEqual(mine.map((user) => user.user_id), [cleo, ben, ada], "Newest signup first");
    assert.ok(mine.every((user) => /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(user.created_at)));
    const columns = ({ user_id: _id, handle: _handle, display_name: _name, created_at: _created, ...rest }: AdminUser) => rest;
    const handle = (id: string) => `u_${id.replaceAll("-", "").slice(0, 12)}`;
    assert.deepEqual(mine.map(columns), [
        {
            handle_set: false, email: null, providers: [], friends: 0, everybody_fight: false, fights: 0,
            referred_by: null, referrals: 0, health_connected: false, last_synced_at: null, app_version: null,
            notifications: false, time_zone: null,
        },
        {
            handle_set: true, email: "ben@example.com", providers: ["google"], friends: 1, everybody_fight: true,
            fights: 1, referred_by: handle(ada), referrals: 0, health_connected: true,
            last_synced_at: "2026-10-18T10:00:00Z", app_version: "1.2.1 (234)", notifications: false, time_zone: null,
        },
        {
            handle_set: true, email: "ada@example.com", providers: ["apple", "google"], friends: 1,
            everybody_fight: false, fights: 1, referred_by: null, referrals: 1, health_connected: false,
            last_synced_at: null, app_version: null, notifications: true, time_zone: "Europe/Paris",
        },
    ]);

    const at = all.users.findIndex((user) => user.user_id === cleo);
    const pages = [await readAdminUsers(1, at, "staging", database), await readAdminUsers(2, at + 1, "staging", database)];
    assert.deepEqual(
        pages.flatMap((page) => page.users.map((user) => user.user_id)),
        all.users.slice(at, at + 3).map((user) => user.user_id),
        "Pages continue where the last one stopped",
    );

    // The Users tab draws the same rows as a server-defined table, in Paris time.
    const dashboard = await readAdminDashboard("users", 30, "staging", database);
    const table = dashboard.tables.find((item) => item.id === "newest_users");
    assert.ok(table);
    assert.equal(table.total, total);
    assert.equal(table.page_size, 20);
    assert.deepEqual(table.rows.map((row) => row.id), all.users.slice(0, 10).map((user) => user.user_id));
    assert.ok(table.rows.every((row) => row.cells.length === table.columns.length), "One cell per column");
    const tablePage = await readAdminTablePage("newest_users", 3, at, "staging", database);
    assert.deepEqual(tablePage.rows.map((row) => row.id), [cleo, ben, ada]);
    assert.deepEqual(tablePage.rows[0].cells[0], { text: "No username", muted: true, bold: false });
    assert.deepEqual(tablePage.rows[1].cells.map((cell) => cell.text).filter((_, index) => index !== 1 && index !== 3), [
        `@${handle(ben)}`, "ben@example.com", "1", "Yes", "1", `@${handle(ada)}`, "0", "Yes", "18 Oct 2026, 12:00",
        "1.2.1 (234)", "No", "Google", "-",
    ]);
    assert.deepEqual(tablePage.rows[2].cells[13], { text: "Apple, Google", muted: false, bold: false });
    await assert.rejects(readAdminTablePage("nothing", 1, 0, "staging", database), /No admin table has this id/);

    // Production reads without the view until its migration reaches `main`.
    const rollback = new Error("rollback");
    await assert.rejects(database.begin(async (transaction) => {
        await transaction`drop view private.account_auth`;
        const before = await readAdminUsers(100, 0, "staging", transaction);
        const ben = before.users.find((user) => user.user_id === users[1]);
        assert.equal(ben?.email, null);
        assert.equal(ben?.providers, null);
        assert.equal(ben?.referred_by, handle(ada));
        assert.match(before.note ?? "", /^Emails and sign-in methods show here once/);
        throw rollback;
    }), rollback);

    const referrers = (await readAdminDashboard("users", 30, "staging", database)).cards
        .find((card) => card.id === "monthly_referrers")?.value ?? 0;
    assert.equal(referrers - referrersBefore, 1, "Ada's link brought Ben");
});
