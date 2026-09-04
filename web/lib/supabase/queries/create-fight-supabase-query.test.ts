import assert from "node:assert/strict";
import { test } from "node:test";
import { createFightSchema } from "./create-fight-supabase-query";

const base = {
  name: "Steps Fight",
  startsAt: "2026-09-04T12:00:00.000Z",
  endsAt: "2026-09-11T12:00:00.000Z",
  timeZone: "Europe/Paris",
  outcomeRule: "highest_total" as const,
  stakeKind: "action" as const,
  actionText: "Cook dinner",
};

test("invite-only create requires at least one username", () => {
  const parsed = createFightSchema.safeParse({
    ...base,
    visibility: "invite_only",
    inviteHandles: [],
  });
  assert.equal(parsed.success, false);
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

test("visibility defaults to invite-only", () => {
  const parsed = createFightSchema.parse({
    ...base,
    inviteHandles: ["leo_runs"],
  });
  assert.equal(parsed.visibility, "invite_only");
  assert.equal(parsed.recurring, false);
});

test("create requires a loser action", () => {
  assert.equal(
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: undefined }).success,
    false,
  );
  assert.equal(
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: "   " }).success,
    false,
  );
});
