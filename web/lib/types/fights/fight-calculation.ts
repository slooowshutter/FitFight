import { z } from "zod";
import { membershipDecisionRowSchema } from "./membership-decision";

const timestampSchema = z.string().refine((value) => Number.isFinite(Date.parse(value)));
export const outcomeRuleValues = ["highest_total", "proportional", "hit_your_goal"] as const;

export const fightCalculationRowSchema = z.object({
  state: membershipDecisionRowSchema.shape.state,
  starts_at: timestampSchema,
  ends_at: timestampSchema,
  final_sync_grace_seconds: z.number().int().nonnegative(),
  outcome_rule: z.enum(outcomeRuleValues),
  stake_minor: z.number().int().nullable(),
  default_goal_value: z.coerce.number().finite().nullable(),
});

export const fightCalculationMemberSchema = z.object({
  user_id: z.string().uuid(),
  personal_target: z.coerce.number().finite().nullable(),
  input_revision: z.number().int().nullable(),
});

export const fightCalculationSnapshotSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  value: z.coerce.number().finite().nonnegative(),
  cutoff_at: timestampSchema,
});

export type FightCalculationRow = z.infer<typeof fightCalculationRowSchema>;
export type FightCalculationMember = z.infer<typeof fightCalculationMemberSchema>;
export type FightCalculationSnapshot = z.infer<typeof fightCalculationSnapshotSchema>;
