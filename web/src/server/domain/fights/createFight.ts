import { z } from "zod";
import { createAdminClient } from "../../db/supabaseAdmin";
import type { FightRow, ProfileRow } from "../../db/types";
import { ApiError, ERROR_CODES } from "../../http";
import { createInvite, lookupProfileByHandle } from "../invites/createInvite";
import { ensureAppleHealthSource } from "../sources/ensureAppleHealthSource";
import { fightSummary } from "./access";

const dateTime = z.string().refine((value) => Number.isFinite(Date.parse(value)), "must be a date-time");

export const createFightSchema = z
  .object({
    name: z.string().min(1).max(80),
    startsAt: dateTime,
    endsAt: dateTime,
    timeZone: z.string().min(1),
    outcomeRule: z.enum(["highest_total", "proportional", "hit_your_goal"]),
    goalPolicy: z.enum(["shared", "personal"]).default("shared"),
    defaultGoalValue: z.number().optional(),
    stakeKind: z.enum(["bragging", "money", "action"]),
    stakeMinor: z.number().int().min(0).optional(),
    currency: z.string().default("USD"),
    actionText: z.string().optional(),
    inviteHandles: z.array(z.string()).optional(),
    start: z.enum(["now", "scheduled"]).default("now"),
    metric: z.literal("steps").optional(),
  })
  .superRefine((value, ctx) => {
    const starts = Date.parse(value.startsAt);
    const ends = Date.parse(value.endsAt);
    if (!Number.isFinite(starts) || !Number.isFinite(ends)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "startsAt and endsAt must be dates" });
      return;
    }
    if (ends <= starts) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "endsAt must be after startsAt" });
    }
  });

export type CreateFightInput = z.infer<typeof createFightSchema>;

const IDEMPOTENCY_WINDOW_MS = 2 * 60 * 1000;

function initialState(input: CreateFightInput): "live" | "scheduled" | "inviting" {
  if (input.start === "now") {
    return "live";
  }
  if ((input.inviteHandles?.length ?? 0) > 0) {
    return "inviting";
  }
  return "scheduled";
}

export async function createFight(userId: string, input: CreateFightInput) {
  if (input.metric && input.metric !== "steps") {
    throw new ApiError(400, ERROR_CODES.invalid_metric, "metric must be steps");
  }

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

  const startsAt = new Date(input.startsAt).toISOString();
  const endsAt = new Date(input.endsAt).toISOString();
  const since = new Date(Date.now() - IDEMPOTENCY_WINDOW_MS).toISOString();

  const { data: existingData, error: existingError } = await admin
    .from("fights")
    .select("id, state")
    .eq("owner_id", userId)
    .eq("name", input.name)
    .eq("starts_at", startsAt)
    .eq("ends_at", endsAt)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not check existing fight");
  }
  if (existingData) {
    return fightSummary(existingData as Pick<FightRow, "id" | "state">);
  }

  const handles = (input.inviteHandles ?? [])
    .map((handle) => handle.trim())
    .filter((handle) => handle.length > 0);
  for (const handle of handles) {
    const invitee = await lookupProfileByHandle(admin, handle);
    if (invitee.user_id === userId) {
      throw new ApiError(400, ERROR_CODES.validation, "Cannot invite yourself");
    }
  }
  const state = initialState({ ...input, inviteHandles: handles });
  const source = await ensureAppleHealthSource(userId, { admin });

  const { data: inserted, error: insertError } = await admin
    .from("fights")
    .insert({
      owner_id: userId,
      name: input.name,
      state,
      starts_at: startsAt,
      ends_at: endsAt,
      time_zone: input.timeZone,
      metric: "steps",
      outcome_rule: input.outcomeRule,
      goal_policy: input.goalPolicy,
      default_goal_value: input.defaultGoalValue ?? null,
      stake_kind: input.stakeKind,
      stake_minor: input.stakeMinor ?? null,
      currency: input.stakeKind === "money" ? input.currency : input.currency ?? null,
      action_text: input.actionText ?? null,
    })
    .select("id, state")
    .single();
  if (insertError || !inserted) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not create fight");
  }

  const nowIso = new Date().toISOString();
  const { error: memberError } = await admin.from("fight_members").insert({
    fight_id: inserted.id,
    user_id: userId,
    state: "accepted",
    accepted_at: nowIso,
    selected_source_id: source.id,
    source_label: source.sourceLabel,
  });
  if (memberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not add owner as member");
  }

  for (const handle of handles) {
    await createInvite(userId, inserted.id as string, handle);
  }

  return fightSummary(inserted as Pick<FightRow, "id" | "state">);
}
