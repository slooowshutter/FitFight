import assert from "node:assert/strict";
import { test } from "node:test";
import { healthKitArchiveSchema } from "./healthKitArchiveBatch";

const mergedDay = {
  day: "2026-08-29",
  starts_at: "2026-08-29T00:00:00.000Z",
  ends_at: "2026-08-30T00:00:00.000Z",
  time_zone: "UTC",
  steps: 1200,
};

test("accepts a bounded HealthKit archive batch and supplies empty collections", () => {
  const parsed = healthKitArchiveSchema.parse({ merged_days: [mergedDay] });
  assert.deepEqual(parsed.samples, []);
  assert.deepEqual(parsed.deletions, []);
  assert.deepEqual(parsed.source_days, []);
  assert.deepEqual(parsed.merged_days, [mergedDay]);
});

test("rejects empty batches and duplicate natural keys", () => {
  assert.equal(healthKitArchiveSchema.safeParse({}).success, false);
  const duplicate = healthKitArchiveSchema.safeParse({
    merged_days: [mergedDay, { ...mergedDay, steps: 1400 }],
  });
  assert.equal(duplicate.success, false);
});

test("rejects invalid time zones and backwards windows", () => {
  assert.equal(
    healthKitArchiveSchema.safeParse({
      merged_days: [{ ...mergedDay, time_zone: "Mars/Olympus" }],
    }).success,
    false,
  );
  assert.equal(
    healthKitArchiveSchema.safeParse({
      merged_days: [{
        ...mergedDay,
        starts_at: "2026-08-30T00:00:00.000Z",
        ends_at: "2026-08-29T00:00:00.000Z",
      }],
    }).success,
    false,
  );
});
