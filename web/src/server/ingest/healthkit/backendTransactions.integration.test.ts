import assert from "node:assert/strict";
import { after, test } from "node:test";
import { closeDatabaseClientForTests, createDatabaseClient } from "../../db/postgres";
import { deleteAccount } from "../../domain/account/deleteAccount";
import { archiveHealthKitSteps } from "./archiveSteps";
import { healthKitArchiveSchema } from "./healthKitArchiveBatch";

const database = createDatabaseClient();
const disposableUser = "44444444-4444-4444-8444-444444444444";
const historicalUser = "55555555-5555-4555-8555-555555555555";

async function makeUser(userId: string, email: string): Promise<void> {
  await database`
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', ${userId}, 'authenticated',
      'authenticated', ${email}, extensions.crypt('password123', extensions.gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      now(), now(), '', '', '', ''
    )
  `;
}

async function cleanup(): Promise<void> {
  await database`delete from public.fights where owner_id in (${disposableUser}, ${historicalUser})`;
  await database`delete from auth.users where id in (${disposableUser}, ${historicalUser})`;
}

after(async () => {
  await cleanup();
  await closeDatabaseClientForTests();
});

test("TypeScript archives HealthKit atomically and owns account deletion", async () => {
  await cleanup();
  await makeUser(disposableUser, "disposable@example.com");
  await makeUser(historicalUser, "historical@example.com");

  const batch = healthKitArchiveSchema.parse({
    samples: [{
      sample_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      value: 1200,
      unit: "count",
      starts_at: "2026-08-29T08:00:00.000Z",
      ends_at: "2026-08-29T09:00:00.000Z",
      local_day: "2026-08-29",
      time_zone: "UTC",
      source_name: "Apple Watch",
      source_bundle_identifier: "com.apple.health",
      metadata: { HKWasUserEntered: { kind: "boolean", value: "false" } },
      user_entered: false,
    }],
    deletions: [{ sample_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }],
    merged_days: [{
      day: "2026-08-29",
      starts_at: "2026-08-29T00:00:00.000Z",
      ends_at: "2026-08-30T00:00:00.000Z",
      time_zone: "UTC",
      steps: 1200,
    }],
    source_days: [{
      day: "2026-08-29",
      starts_at: "2026-08-29T00:00:00.000Z",
      ends_at: "2026-08-30T00:00:00.000Z",
      time_zone: "UTC",
      source_name: "Apple Watch",
      source_bundle_identifier: "com.apple.health",
      steps: 1200,
    }],
    sync: {
      time_zone: "UTC",
      accessible_from: "2026-08-29T08:00:00.000Z",
      complete_through: "2026-08-29T09:00:00.000Z",
    },
  });

  const ack = await archiveHealthKitSteps(historicalUser, batch, database, async () => []);
  assert.equal(ack.samples, 1);
  assert.equal(ack.deletions, 1);
  assert.equal(ack.mergedDays, 1);
  assert.equal(ack.sourceDays, 1);

  const [archiveCounts] = await database<{
    samples: number;
    deletions: number;
    source_days: number;
    syncs: number;
    observations: number;
    steps: number;
  }[]>`
    select
      (select count(*)::integer from private.healthkit_step_samples where user_id = ${historicalUser}) as samples,
      (select count(*)::integer from private.healthkit_step_sample_deletions where user_id = ${historicalUser}) as deletions,
      (select count(*)::integer from private.healthkit_step_source_days where user_id = ${historicalUser}) as source_days,
      (select count(*)::integer from private.healthkit_step_syncs where user_id = ${historicalUser}) as syncs,
      (select count(*)::integer from private.metric_observations where user_id = ${historicalUser}) as observations,
      (select steps from public.step_days where user_id = ${historicalUser} and day = date '2026-08-29')::integer as steps
  `;
  assert.deepEqual(archiveCounts, {
    samples: 1,
    deletions: 1,
    source_days: 1,
    syncs: 1,
    observations: 1,
    steps: 1200,
  });

  await database`
    insert into public.fights (
      owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
    ) values (
      ${historicalUser}, 'History', 'final',
      '2026-08-29T00:00:00.000Z', '2026-08-30T00:00:00.000Z',
      'UTC', 'highest_total', 'shared'
    )
  `;

  await deleteAccount(disposableUser, database);
  await deleteAccount(historicalUser, database);

  const [deletion] = await database<{
    disposable_auth: number;
    historical_auth: number;
    historical_profiles: number;
    historical_samples: number;
    historical_steps: number;
    historical_email: string | null;
  }[]>`
    select
      (select count(*)::integer from auth.users where id = ${disposableUser}) as disposable_auth,
      (select count(*)::integer from auth.users where id = ${historicalUser}) as historical_auth,
      (select count(*)::integer from public.profiles where user_id = ${historicalUser} and deleted_at is not null) as historical_profiles,
      (select count(*)::integer from private.healthkit_step_samples where user_id = ${historicalUser}) as historical_samples,
      (select count(*)::integer from public.step_days where user_id = ${historicalUser}) as historical_steps,
      (select email from auth.users where id = ${historicalUser}) as historical_email
  `;
  assert.deepEqual(deletion, {
    disposable_auth: 0,
    historical_auth: 1,
    historical_profiles: 1,
    historical_samples: 0,
    historical_steps: 0,
    historical_email: null,
  });
});
