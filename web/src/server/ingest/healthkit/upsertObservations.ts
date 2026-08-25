import { z } from "zod";
import { createAdminClient, observationsTable } from "../../db/supabaseAdmin";
import type { ProfileRow } from "../../db/types";
import { ensureAppleHealthSource } from "../../domain/sources/ensureAppleHealthSource";
import { ApiError, ERROR_CODES } from "../../http";
import { civilDayBounds, isCivilDay, resolveTimeZone } from "../../scoring/civilDay";
import { listFightsToRecalculate, recalculateFight } from "../../scoring/recalculateFight";

const daySchema = z.object({
  day: z
    .string()
    .refine(isCivilDay, "day must be YYYY-MM-DD"),
  value: z.number().min(0),
  revision: z.number().int().min(1).optional().default(1),
});

export const healthKitBatchSchema = z.object({
  idempotencyKey: z.string().min(8).max(128),
  sourceLabel: z.string().optional(),
  contributingSourceLabels: z.array(z.string()).optional(),
  days: z.array(daySchema).min(1).max(400),
});

export type HealthKitBatch = z.infer<typeof healthKitBatchSchema>;

export type BatchAck = {
  upserted: number;
  sourceId: string;
  recalculatedFightIds: string[];
};

export async function upsertHealthKitObservations(
  userId: string,
  batch: HealthKitBatch,
): Promise<BatchAck> {
  const admin = createAdminClient();
  const { data: profileData, error: profileError } = await admin
    .from("profiles")
    .select("user_id, handle, display_name, time_zone")
    .eq("user_id", userId)
    .maybeSingle();
  if (profileError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load profile");
  }
  const profile = profileData as ProfileRow | null;
  if (!profile) {
    throw new ApiError(400, ERROR_CODES.profile_missing, "Profile is missing");
  }

  const timeZone = resolveTimeZone(profile.time_zone);
  const rows = batch.days.map((day) => {
    const bounds = civilDayBounds(day.day, timeZone);
    return {
      user_id: userId,
      external_record_id: bounds.externalRecordId,
      metric: "steps",
      starts_at: bounds.startsAt.toISOString(),
      ends_at: bounds.endsAt.toISOString(),
      value: day.value,
      unit: "steps",
      revision: day.revision,
      provenance: {
        route: "healthkit",
        idempotencyKey: batch.idempotencyKey,
        contributingSourceLabels: batch.contributingSourceLabels ?? [],
      },
      retracted_at: null,
    };
  });

  const completeThrough = rows.reduce((max, row) => (row.ends_at > max ? row.ends_at : max), rows[0].ends_at);
  const source = await ensureAppleHealthSource(userId, {
    admin,
    sourceLabel: batch.sourceLabel,
    contributingSourceLabels: batch.contributingSourceLabels,
    completeThrough,
  });

  const payload = rows.map((row) => ({ ...row, source_id: source.id }));
  const { error: upsertError } = await observationsTable(admin)
    .upsert(payload, { onConflict: "source_id,external_record_id,revision" });
  if (upsertError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not upsert observations");
  }

  const fightIds = await listFightsToRecalculate(userId, admin);
  for (const fightId of fightIds) {
    await recalculateFight(fightId, admin);
  }

  return {
    upserted: payload.length,
    sourceId: source.id,
    recalculatedFightIds: fightIds,
  };
}
