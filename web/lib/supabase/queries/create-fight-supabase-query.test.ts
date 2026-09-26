import { createFightSchema } from "@/lib/types/fights/create-fight";
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { storedFightIdentity } from "./create-fight-supabase-query";

const base = {
    name: "Steps Fight",
    startsAt: "2026-09-04T12:00:00.000Z",
    endsAt: "2026-09-11T12:00:00.000Z",
    timeZone: "Europe/Paris",
    outcomeRule: "highest_total" as const,
    stakeKind: "action" as const,
    actionText: "Cook dinner",
};

test("custom Fight time zones must be recognized IANA zones", () => {
    assert.equal(createFightSchema.safeParse({ ...base, timeZone: "Pacific/Kiritimati" }).success, true);
    assert.equal(createFightSchema.safeParse({ ...base, timeZone: "Nowhere/Invalid" }).success, false);
});

test("private create can start with the owner alone", () => {
    const parsed = createFightSchema.parse({
        ...base,
        visibility: "invite_only",
        inviteHandles: [],
    });
    assert.equal(parsed.visibility, "invite_only");
    assert.deepEqual(parsed.inviteHandles, []);
});

test("joinable create can start with the owner alone", () => {
    const parsed = createFightSchema.parse({
        ...base,
        visibility: "joinable",
        recurring: true,
    });
    assert.equal(parsed.visibility, "joinable");
    assert.equal(parsed.recurring, true);
    assert.deepEqual(parsed.inviteHandles, undefined);
});

test("visibility defaults to invite-only and recurring is on", () => {
    const parsed = createFightSchema.parse({
        ...base,
        inviteHandles: ["leo_runs"],
    });
    assert.equal(parsed.visibility, "invite_only");
    assert.equal(parsed.recurring, true);
});

test("create can turn recurring off", () => {
    const parsed = createFightSchema.parse({
        ...base,
        visibility: "joinable",
        recurring: false,
    });
    assert.equal(parsed.recurring, false);
});

test("create allows an optional title and action", () => {
    assert.equal(
        createFightSchema.safeParse({
            ...base,
            visibility: "joinable",
            actionText: undefined,
        }).success,
        true,
    );
    assert.equal(
        createFightSchema.safeParse({
            ...base,
            visibility: "joinable",
            actionText: "   ",
            name: "",
        }).success,
        true,
    );
    assert.deepEqual(storedFightIdentity("Office steps", "Cook dinner"), {
        name: "Office steps",
        actionText: "Cook dinner",
    });
    assert.deepEqual(storedFightIdentity("", "Cook dinner"), {
        name: "Cook dinner",
        actionText: "Cook dinner",
    });
    assert.deepEqual(storedFightIdentity("Office steps", "  "), {
        name: "Office steps",
        actionText: null,
    });
    assert.deepEqual(storedFightIdentity("  ", undefined), {
        name: "Steps Fight",
        actionText: null,
    });
});

test("custom schedules preserve exact times and reject reversed windows", () => {
    const input = {
        ...base,
        start: "scheduled",
        startsAt: "2026-09-14T09:15:00+02:00",
        endsAt: "2026-09-14T10:45:00+02:00",
    };
    const parsed = createFightSchema.parse(input);
    assert.equal(parsed.startsAt, input.startsAt);
    assert.equal(parsed.endsAt, input.endsAt);
    assert.equal(parsed.start, "scheduled");
    assert.equal(
        createFightSchema.safeParse({ ...input, endsAt: input.startsAt })
            .success,
        false,
    );
    assert.equal(
        createFightSchema.safeParse({
            ...input,
            startsAt: input.endsAt,
            endsAt: input.startsAt,
        }).success,
        false,
    );
});

for (const start of ["now", "scheduled"] as const) {
    test(`${start} creation with invitees preserves its clock state and timestamps`, async (t) => {
        const state = start === "now" ? "live" : "scheduled";
        const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const savedKey = process.env.SUPABASE_SECRET_KEY;
        process.env.NEXT_PUBLIC_SUPABASE_URL = "https://schedules.example";
        process.env.SUPABASE_SECRET_KEY = "test-only-key";
        t.after(() => {
            if (savedURL === undefined)
                delete process.env.NEXT_PUBLIC_SUPABASE_URL;
            else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
            if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
            else process.env.SUPABASE_SECRET_KEY = savedKey;
        });
        const owner = "11111111-1111-4111-8111-111111111111";
        const invitee = "33333333-3333-4333-8333-333333333333";
        const seriesId = "44444444-4444-4444-8444-444444444444";
        const fightId = "22222222-2222-4222-8222-222222222222";
        t.mock.method(
            globalThis,
            "fetch",
            async (input: RequestInfo | URL, init?: RequestInit) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                assert.equal(url.hostname, "schedules.example");
                if (url.pathname === "/rest/v1/data_sources") {
                    return Response.json(
                        request.method === "GET"
                            ? []
                            : {
                                  id: "health-source",
                                  source_label: "Apple Health",
                                  contributing_source_labels: [],
                              },
                    );
                }
                // Every Fight row is written inside the database transaction.
                assert.equal(request.method, "GET");
                switch (url.pathname) {
                    case "/rest/v1/profiles":
                        return Response.json([
                            {
                                user_id: url.searchParams.has("handle")
                                    ? invitee
                                    : owner,
                                handle: "leo_runs",
                                display_name: "Leo",
                                time_zone: "Europe/Paris",
                            },
                        ]);
                    case "/rest/v1/fights":
                    case "/rest/v1/fight_series":
                        return Response.json([]);
                    default:
                        throw new Error(`Unexpected query: ${url.pathname}`);
                }
            },
        );
        const statements: { text: string; values: unknown[] }[] = [];
        let transactions = 0;
        const sql = ((first: unknown, ...values: unknown[]) => {
            if (!Array.isArray(first) || !("raw" in first)) return first;
            const text = (first as string[]).join("?").replace(/\s+/g, " ");
            statements.push({ text, values });
            if (text.includes("insert into public.fight_series (") && text.includes("returning id")) {
                return Promise.resolve([{ id: seriesId }]);
            }
            if (text.includes("insert into public.fights (")) {
                return Promise.resolve([{ id: fightId, state }]);
            }
            return Promise.resolve([]);
        }) as unknown as Sql;
        sql.begin = ((callback: (transaction: Sql) => Promise<unknown>) => {
            transactions += 1;
            return callback(sql);
        }) as unknown as Sql["begin"];
        const { createFight } = await import("./create-fight-supabase-query");
        const result = await createFight(
            owner,
            createFightSchema.parse({
                ...base,
                start,
                inviteHandles: ["leo_runs", "leo_runs"],
            }),
            sql,
        );
        assert.deepEqual(result, { id: fightId, state });
        assert.equal(transactions, 1);
        const fightInsert = statements.find((statement) =>
            statement.text.includes("insert into public.fights ("),
        );
        assert.deepEqual(fightInsert?.values, [
            owner, base.name, state, base.startsAt, base.endsAt, base.timeZone,
            "highest_total", "shared", null, "action", null, "USD",
            base.actionText, seriesId,
        ]);
        const invitations = statements.filter(
            (statement) =>
                statement.text.includes("insert into") &&
                statement.values.some((value) => Array.isArray(value) && value.includes(invitee)),
        );
        assert.deepEqual(
            invitations.map((statement) => statement.text.match(/insert into public\.(\w+)/)?.[1]),
            ["fight_members", "fight_series_members", "fight_invites"],
        );
        for (const statement of invitations) {
            assert.deepEqual(statement.values.find(Array.isArray), [invitee], "Duplicate handles invite once");
        }
    });
}
