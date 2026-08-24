import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "../../db/supabaseAdmin";
import type { DataSourceRow } from "../../db/types";
import { ApiError, ERROR_CODES } from "../../http";

export type AppleHealthSource = {
  id: string;
  provider: "apple_health";
  sourceLabel: string;
  contributingSourceLabels: string[];
};

const PROVIDER = "apple_health";
const CONNECTION_ROUTE = "healthkit";
const DEFAULT_LABEL = "Apple Health";

export async function ensureAppleHealthSource(
  userId: string,
  options: {
    sourceLabel?: string;
    contributingSourceLabels?: string[];
    completeThrough?: string | null;
    admin?: SupabaseClient;
  } = {},
): Promise<AppleHealthSource> {
  const admin = options.admin ?? createAdminClient();
  const sourceLabel = options.sourceLabel?.trim() || DEFAULT_LABEL;
  const contributing = options.contributingSourceLabels ?? [];

  const { data: existingData, error: existingError } = await admin
    .from("data_sources")
    .select(
      "id, user_id, provider, source_label, contributing_source_labels, connection_route, status, complete_through",
    )
    .eq("user_id", userId)
    .eq("provider", PROVIDER)
    .eq("connection_route", CONNECTION_ROUTE)
    .maybeSingle();
  if (existingError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load Apple Health source");
  }

  const existing = existingData as DataSourceRow | null;
  const nowIso = new Date().toISOString();

  if (existing) {
    const completeThrough =
      options.completeThrough &&
      (!existing.complete_through || options.completeThrough > existing.complete_through)
        ? options.completeThrough
        : existing.complete_through;
    const { data: updated, error: updateError } = await admin
      .from("data_sources")
      .update({
        source_label: sourceLabel,
        contributing_source_labels: contributing.length
          ? contributing
          : existing.contributing_source_labels,
        status: "healthy",
        revoked_at: null,
        last_success_at: nowIso,
        last_error_code: null,
        complete_through: completeThrough,
      })
      .eq("id", existing.id)
      .select("id, source_label, contributing_source_labels")
      .single();
    if (updateError || !updated) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not update Apple Health source");
    }
    return {
      id: updated.id as string,
      provider: PROVIDER,
      sourceLabel: updated.source_label as string,
      contributingSourceLabels: (updated.contributing_source_labels as string[]) ?? [],
    };
  }

  const { data: inserted, error: insertError } = await admin
    .from("data_sources")
    .insert({
      user_id: userId,
      provider: PROVIDER,
      source_label: sourceLabel,
      contributing_source_labels: contributing,
      connection_route: CONNECTION_ROUTE,
      capabilities: ["steps"],
      status: "healthy",
      consent_version: 1,
      connected_at: nowIso,
      last_success_at: nowIso,
      complete_through: options.completeThrough ?? null,
    })
    .select("id, source_label, contributing_source_labels")
    .single();
  if (insertError || !inserted) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not create Apple Health source");
  }
  return {
    id: inserted.id as string,
    provider: PROVIDER,
    sourceLabel: inserted.source_label as string,
    contributingSourceLabels: (inserted.contributing_source_labels as string[]) ?? [],
  };
}

export function toDataSourceResponse(source: AppleHealthSource) {
  return {
    id: source.id,
    provider: source.provider,
    sourceLabel: source.sourceLabel,
    contributingSourceLabels: source.contributingSourceLabels,
  };
}
