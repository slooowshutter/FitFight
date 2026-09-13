import assert from "node:assert/strict";
import { test } from "node:test";
import { createFightSchema, storedFightIdentity } from "./create-fight-supabase-query";

const base = {
  name: "Steps Fight",
  startsAt: "2026-09-04T12:00:00.000Z",
  endsAt: "2026-09-11T12:00:00.000Z",
  timeZone: "Europe/Paris",
  outcomeRule: "highest_total" as const,
  stakeKind: "action" as const,
  actionText: "Cook dinner",
};

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
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: undefined }).success,
    true,
  );
  assert.equal(
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: "   ", name: "" }).success,
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
  const input = { ...base, start: "scheduled", startsAt: "2026-09-14T09:15:00+02:00", endsAt: "2026-09-14T10:45:00+02:00" };
  const parsed = createFightSchema.parse(input);
  assert.equal(parsed.startsAt, input.startsAt);
  assert.equal(parsed.endsAt, input.endsAt);
  assert.equal(parsed.start, "scheduled");
  assert.equal(createFightSchema.safeParse({ ...input, endsAt: input.startsAt }).success, false);
  assert.equal(createFightSchema.safeParse({ ...input, startsAt: input.endsAt, endsAt: input.startsAt }).success, false);
});

for (const start of ["now", "scheduled"] as const) {
  test(`${start} creation with invitees preserves its clock state and timestamps`, async (t) => {
    const state = start === "now" ? "live" : "scheduled";
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://schedules.example";
    process.env.SUPABASE_SECRET_KEY = "test-only-key";
    t.after(() => {
      if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
      else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
      if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
      else process.env.SUPABASE_SECRET_KEY = savedKey;
    });
    let fightWrites = 0;
    let inviteWrites = 0;
    const owner = "11111111-1111-4111-8111-111111111111";
    const fight = { id: "22222222-2222-4222-8222-222222222222", owner_id: owner, state, ends_at: base.endsAt };
    t.mock.method(globalThis, "fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      assert.equal(url.hostname, "schedules.example");
      switch (url.pathname) {
        case "/rest/v1/profiles":
          return Response.json([{ user_id: url.searchParams.has("handle") ? "33333333-3333-4333-8333-333333333333" : owner,
            handle: "leo_runs", display_name: "Leo", time_zone: "Europe/Paris" }]);
        case "/rest/v1/fights":
          if (request.method === "GET") return Response.json(url.searchParams.has("id") ? [fight] : []);
          assert.equal(request.method, "POST");
          fightWrites += 1;
          assert.deepEqual(await request.json(), {
            owner_id: owner, name: base.name, state, starts_at: base.startsAt, ends_at: base.endsAt,
            time_zone: base.timeZone, metric: "steps", outcome_rule: "highest_total", goal_policy: "shared",
            default_goal_value: null, stake_kind: "action", stake_minor: null, currency: "USD", action_text: base.actionText,
            series_id: "44444444-4444-4444-8444-444444444444",
          });
          return Response.json(fight);
        case "/rest/v1/data_sources":
          return Response.json(request.method === "GET" ? [] : { id: "health-source", source_label: "Apple Health", contributing_source_labels: [] });
        case "/rest/v1/fight_series":
          if (request.method === "GET") return Response.json([]);
          if (request.method === "POST") return Response.json({ id: "44444444-4444-4444-8444-444444444444" });
          return new Response(null, { status: 204 });
        case "/rest/v1/fight_members":
          return request.method === "GET" ? Response.json([]) : new Response(null, { status: 204 });
        case "/rest/v1/fight_series_members":
          return new Response(null, { status: 204 });
        case "/rest/v1/fight_invites":
          inviteWrites += 1;
          return new Response(null, { status: 204 });
        default: throw new Error(`Unexpected query: ${url.pathname}`);
      }
    });
    const { createFight } = await import("./create-fight-supabase-query");
    const result = await createFight(owner, createFightSchema.parse({ ...base, start, inviteHandles: ["leo_runs"] }));
    assert.deepEqual(result, { id: fight.id, state });
    assert.equal(fightWrites, 1);
    assert.equal(inviteWrites, 1);
  });
}
