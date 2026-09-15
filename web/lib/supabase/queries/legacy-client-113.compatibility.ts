import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import contract from "../../../../contracts/fixtures/legacy-build-113.json";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { legacyMembership113Schema } from "@/lib/types/testing/legacy-client";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
after(() => database.end());

test("public build 113 can name its profile, create, invite, accept, decline, and read after migration", async (t) => {
  const accounts = [];
  const userIds: string[] = [];
  t.after(async () => {
    await database`delete from public.fights where owner_id = any(${database.array(userIds)}::uuid[])`;
    await database`delete from auth.users where id = any(${database.array(userIds)}::uuid[])`;
  });
  for (let index = 0; index < 3; index++) {
    const email = `legacy-${randomUUID()}@example.com`;
    const password = randomUUID();
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    assert.equal(created.error, null);
    assert.ok(created.data.user);
    const userId = created.data.user.id;
    userIds.push(userId);
    const client = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    assert.equal((await client.auth.signInWithPassword({ email, password })).error, null);
    const handle = `ci_${randomUUID().replaceAll("-", "").slice(0, 20)}`;
    assert.equal((await client.from("profiles").update({
      handle, handle_set_at: new Date().toISOString(), display_name: "Legacy Person",
    }).eq("user_id", userId)).error, null);
    accounts.push({ client, userId, handle });
  }
  const [owner, invitee, stranger] = accounts;
  const profiles = await owner.client.from("profiles").select(contract.profile_select)
    .in("handle", [invitee.handle]);
  assert.equal(profiles.error, null);
  assert.deepEqual(profiles.data, [{ user_id: invitee.userId, handle: invitee.handle, display_name: "Legacy Person" }]);

  const now = new Date().toISOString();
  const created = await owner.client.from("fights").insert({
    ...contract.fight_insert, owner_id: owner.userId, starts_at: now,
    ends_at: new Date(Date.now() + 3_600_000).toISOString(),
  }).select("id").single();
  assert.equal(created.error, null);
  assert.ok(created.data);
  const fightId = created.data.id;
  assert.equal(typeof fightId, "string");
  assert.equal((await owner.client.from("fight_members").insert([
    { fight_id: fightId, user_id: owner.userId, state: "accepted", accepted_at: now },
    { fight_id: fightId, user_id: invitee.userId, state: "invited" },
  ])).error, null);

  assert.equal((await stranger.client.from("fight_members").insert({
    fight_id: fightId, user_id: stranger.userId, state: "accepted", accepted_at: now,
  })).error?.code, "42501", "strangers cannot join a private fight");
  assert.equal((await owner.client.from("fight_members").insert({
    fight_id: fightId, user_id: stranger.userId, state: "accepted", accepted_at: now,
  })).error?.code, "42501", "owners cannot accept for another person");
  assert.equal((await invitee.client.from("fight_members").update({
    ...contract.accept_update, accepted_at: now,
  }).eq("fight_id", fightId).eq("user_id", invitee.userId)).error, null);

  const members = await invitee.client.from("fight_members").select(contract.member_select).eq("fight_id", fightId);
  assert.equal(members.error, null);
  assert.ok(members.data);
  assert.equal(members.data.length, 2);
  for (const row of legacyMembership113Schema.array().parse(members.data)) {
    assert.deepEqual(Object.keys(row).sort(), contract.member_select.split(",").sort());
    assert.equal(row.state, "accepted");
    assert.equal(row.current_value, null);
    assert.equal(row.final_value, null);
    assert.equal(row.rank, null);
  }
  assert.equal((await invitee.client.from("fight_members").update({ current_value: 999999 })
    .eq("fight_id", fightId).eq("user_id", invitee.userId)).error?.code, "42501");
  assert.equal((await owner.client.from("fights").update({ state: "final" }).eq("id", fightId)).error?.code, "42501");
  const fights = await invitee.client.from("fights").select(contract.fight_select).eq("id", fightId).single();
  assert.equal(fights.error, null);
  assert.ok(fights.data);
  assert.deepEqual(Object.keys(fights.data).sort(), contract.fight_select.split(",").sort());
  const steps = await invitee.client.from("step_days").select(contract.steps_select).eq("user_id", owner.userId);
  assert.equal(steps.error, null);

  assert.equal((await owner.client.from("fight_members").insert({
    fight_id: fightId, user_id: stranger.userId, state: "invited",
  })).error, null);
  assert.equal((await stranger.client.from("fight_members").update(contract.decline_update)
    .eq("fight_id", fightId).eq("user_id", stranger.userId)).error, null);
  const declined = await stranger.client.from("fight_members").select("state")
    .eq("fight_id", fightId).eq("user_id", stranger.userId).single();
  assert.equal(declined.error, null);
  assert.deepEqual(declined.data, { state: "declined" });
});
