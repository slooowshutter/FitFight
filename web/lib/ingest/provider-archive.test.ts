import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { readProviderArchive, requireProviderArchiveSize } from "./provider-archive";

const mebibyte = 1_024 * 1_024;

test("provider archives may exceed the obsolete 50 MiB limit", () => {
  assert.doesNotThrow(() => requireProviderArchiveSize(60 * mebibyte));
  assert.throws(
    () => requireProviderArchiveSize(513 * mebibyte),
    /Archive exceeds 512 MiB/,
  );
});

test("raw HealthKit events can be consumed without retaining them in the archive summary", async () => {
  const records = [
    {
      type: "sample",
      operation: "add",
      sample_id: "333822a8-8577-4d9d-8145-ab5f120ee42f",
      value: 42,
      unit: "count",
      starts_at: "2026-08-30T12:00:00.000Z",
      ends_at: "2026-08-30T12:05:00.000Z",
      local_day: "2026-08-30",
      time_zone: "Europe/Paris",
      source_name: "iPhone",
      source_bundle_identifier: "com.apple.health",
      source_version: null,
      source_product_type: null,
      source_os_version: "26.0.0",
      device_name: null,
      device_manufacturer: null,
      device_model: null,
      device_hardware_version: null,
      device_firmware_version: null,
      device_software_version: null,
      device_local_identifier: null,
      device_udi_identifier: null,
      metadata: {},
      user_entered: false,
    },
    {
      type: "checkpoint",
      time_zone: "Europe/Paris",
      accessible_from: "2026-08-30T12:00:00.000Z",
      complete_through: "2026-08-30T13:00:00.000Z",
    },
  ];
  const archive = `${records.map((record) => JSON.stringify(record)).join("\n")}\n`;
  const bytes = new TextEncoder().encode(archive);
  const events: string[] = [];

  const result = await readProviderArchive(
    new Blob([bytes]).stream(),
    bytes.byteLength,
    createHash("sha256").update(bytes).digest("hex"),
    async (item) => {
      events.push(item.record.sample_id);
    },
  );

  assert.deepEqual(events, ["333822a8-8577-4d9d-8145-ab5f120ee42f"]);
  assert.equal(result.sampleCount, 1);
  assert.equal(result.deletionCount, 0);
  assert.deepEqual(result.records.map((item) => item.record.type), ["checkpoint"]);
});

test("an archive larger than 50 MiB is parsed without retaining raw samples", async () => {
  const metadata = Object.fromEntries(Array.from({ length: 100 }, (_, index) => [
    `field_${index}`,
    { kind: "string", value: "x".repeat(8_000), objc_type: null },
  ]));
  const sample = {
    type: "sample",
    operation: "add",
    sample_id: "333822a8-8577-4d9d-8145-000000000000",
    value: 42,
    unit: "count",
    starts_at: "2026-08-30T12:00:00.000Z",
    ends_at: "2026-08-30T12:05:00.000Z",
    local_day: "2026-08-30",
    time_zone: "Europe/Paris",
    source_name: "iPhone",
    source_bundle_identifier: "com.apple.health",
    source_version: null,
    source_product_type: null,
    source_os_version: "26.0.0",
    device_name: null,
    device_manufacturer: null,
    device_model: null,
    device_hardware_version: null,
    device_firmware_version: null,
    device_software_version: null,
    device_local_identifier: null,
    device_udi_identifier: null,
    metadata,
    user_entered: false,
  };
  const checkpoint = new TextEncoder().encode(`${JSON.stringify({
    type: "checkpoint",
    time_zone: "Europe/Paris",
    accessible_from: "2026-08-30T12:00:00.000Z",
    complete_through: "2026-08-30T13:00:00.000Z",
  })}\n`);
  const templateBytes = new TextEncoder().encode(`${JSON.stringify(sample)}\n`).byteLength;
  const repetitions = Math.ceil((60 * mebibyte) / templateBytes);
  const hash = createHash("sha256");
  let expectedBytes = checkpoint.byteLength;
  for (let index = 0; index < repetitions; index += 1) {
    const line = new TextEncoder().encode(`${JSON.stringify({
      ...sample,
      sample_id: `333822a8-8577-4d9d-8145-${index.toString(16).padStart(12, "0")}`,
    })}\n`);
    expectedBytes += line.byteLength;
    hash.update(line);
  }
  hash.update(checkpoint);

  let index = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (index < repetitions) {
        controller.enqueue(new TextEncoder().encode(`${JSON.stringify({
          ...sample,
          sample_id: `333822a8-8577-4d9d-8145-${index.toString(16).padStart(12, "0")}`,
        })}\n`));
        index += 1;
      } else {
        controller.enqueue(checkpoint);
        controller.close();
      }
    },
  });

  const result = await readProviderArchive(stream, expectedBytes, hash.digest("hex"));

  assert.ok(result.actualBytes > 50 * mebibyte);
  assert.equal(result.sampleCount, repetitions);
  assert.deepEqual(result.records.map((item) => item.record.type), ["checkpoint"]);
});
