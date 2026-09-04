import { rollingWindow } from "@/lib/domain/fights/join-code";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightRow, FightSeriesRow } from "@/lib/types/database";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";

const MEMBER_SELECT = "fight_id, user_id, state, selected_source_id, source_label";

type SeriesMember = {
  series_id: string;
  user_id: string;
  state: string;
};

export async function mintNextRecurringFight(
  previousFightId: string,
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<string | null> {
  const { data: fightData, error: fightError } = await admin
    .from("fights")
    .select("*")
    .eq("id", previousFightId)
    .maybeSingle();
  if (fightError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
  }
  const previous = fightData as FightRow | null;
  if (!previous?.series_id) {
    return null;
  }
  if (Date.parse(previous.ends_at) > now.getTime()) {
    return null;
  }

  const { data: seriesData, error: seriesError } = await admin
    .from("fight_series")
    .select("*")
    .eq("id", previous.series_id)
    .maybeSingle();
  if (seriesError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
  }
  const series = seriesData as FightSeriesRow | null;
  if (!series?.recurring || series.paused_at) {
    return null;
  }

  const window = rollingWindow(previous.starts_at, previous.ends_at);
  const { data: existingData, error: existingError } = await admin
    .from("fights")
    .select("id")
    .eq("series_id", series.id)
    .eq("starts_at", window.startsAt)
    .maybeSingle();
  if (existingError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not check next fight");
  }
  if (existingData) {
    const existingId = existingData.id as string;
    await admin
      .from("fight_series")
      .update({ current_fight_id: existingId })
      .eq("id", series.id)
      .is("paused_at", null);
    return existingId;
  }

  const { data: inserted, error: insertError } = await admin
    .from("fights")
    .insert({
      owner_id: previous.owner_id,
      name: previous.name,
      state: "live",
      starts_at: window.startsAt,
      ends_at: window.endsAt,
      time_zone: previous.time_zone,
      metric: "steps",
      outcome_rule: previous.outcome_rule,
      goal_policy: previous.goal_policy,
      default_goal_value: previous.default_goal_value,
      stake_kind: previous.stake_kind,
      stake_minor: previous.stake_minor,
      currency: previous.currency,
      action_text: previous.action_text,
      series_id: series.id,
    })
    .select("id")
    .single();
  if (insertError?.code === "23505") {
    const { data: raced } = await admin
      .from("fights")
      .select("id")
      .eq("series_id", series.id)
      .eq("starts_at", window.startsAt)
      .maybeSingle();
    return (raced?.id as string | undefined) ?? null;
  }
  if (insertError || !inserted) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not mint next fight");
  }

  const nextId = inserted.id as string;
  const { data: rosterData, error: rosterError } = await admin
    .from("fight_series_members")
    .select("series_id, user_id, state")
    .eq("series_id", series.id)
    .eq("state", "accepted");
  if (rosterError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load series roster");
  }
  const roster = (rosterData ?? []) as SeriesMember[];
  const nowIso = now.toISOString();
  for (const member of roster) {
    const source = await ensureAppleHealthSource(member.user_id, { admin });
    const { error: memberError } = await admin.from("fight_members").insert({
      fight_id: nextId,
      user_id: member.user_id,
      state: "accepted",
      accepted_at: nowIso,
      selected_source_id: source.id,
      source_label: source.sourceLabel,
    });
    if (memberError && memberError.code !== "23505") {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not copy series roster");
    }
  }

  await admin.from("fight_series").update({ current_fight_id: nextId }).eq("id", series.id);
  return nextId;
}

export async function mintDueRecurringFights(
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<string[]> {
  const { data, error } = await admin
    .from("fight_series")
    .select("id, current_fight_id")
    .eq("recurring", true)
    .is("paused_at", null);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load recurring series");
  }
  const minted: string[] = [];
  for (const row of data ?? []) {
    const currentId = row.current_fight_id as string | null;
    if (!currentId) {
      continue;
    }
    const nextId = await mintNextRecurringFight(currentId, admin, now);
    if (nextId && nextId !== currentId) {
      minted.push(nextId);
    }
  }
  return minted;
}
