import { z } from "zod";
import { aiWorkflowSchema } from "@/lib/types/ai/workflow";
import { aiCreditStateValues } from "@/lib/types/ai/credits";
import { aiErrorCodeSchema } from "@/lib/types/ai/error";
import {
    blendRunHandleSchema,
    blendWorkflowVersionSchema,
} from "@/lib/types/blend/workflow";

export const aiRequestStateValues = [
    "starting",
    "pending",
    "running",
    "completed",
    "failed",
    "cancelled",
    "start_unconfirmed",
] as const;

export const aiAdmissionLimitsSchema = z.object({
    globalDailyStarts: z.number().int().positive(),
    globalConcurrentRuns: z.number().int().positive(),
    providerRequestsPerMinute: z.number().int().positive(),
});

export const aiRequestReservationSchema = z.object({
    workflow: aiWorkflowSchema,
    resourceId: z.string().uuid().nullable(),
    idempotencyKey: z.string().uuid(),
    requestHash: z.string().regex(/^[a-f0-9]{64}$/),
    version: blendWorkflowVersionSchema.nullable(),
    creditPrice: z.number().int().positive().nullable(),
    sourceRequestIds: z.array(z.string().uuid()).max(5),
});

export const aiRequestRecordSchema = z.object({
    id: z.string().uuid(),
    user_id: z.string().uuid(),
    workflow: aiWorkflowSchema,
    resource_id: z.string().uuid().nullable(),
    idempotency_key: z.string().uuid(),
    request_hash: z.string(),
    workflow_version: blendWorkflowVersionSchema,
    run_handle: blendRunHandleSchema.nullable(),
    status: z.enum(aiRequestStateValues),
    result: z.record(z.unknown()).nullable(),
    error_code: aiErrorCodeSchema.nullable(),
    created_at: z.coerce.date(),
    updated_at: z.coerce.date(),
    lease_token: z.string().uuid().nullable(),
    lease_expires_at: z.coerce.date().nullable(),
    next_poll_at: z.coerce.date(),
    source_request_ids: z.array(z.string().uuid()),
    credit_price: z.number().int().nonnegative(),
    credit_state: z.enum(aiCreditStateValues),
    admitted_at: z.coerce.date().nullable(),
    submission_attempted_at: z.coerce.date().nullable(),
    acknowledged_at: z.coerce.date().nullable(),
    provider_completed_at: z.coerce.date().nullable(),
    terminal_observed_at: z.coerce.date().nullable(),
    settled_at: z.coerce.date().nullable(),
    recovery_operation_key: z.string().uuid().nullable(),
    recovery_actor: z.string().uuid().nullable(),
    recovery_evidence: z.string().nullable(),
});

export const aiPollRecordSchema = aiRequestRecordSchema.extend({
    poll_due: z.boolean(),
});

export const aiRequestUpdateSchema = z.object({
    status: z.enum(aiRequestStateValues).exclude(["starting"]),
    runHandle: blendRunHandleSchema.nullable(),
    result: z.record(z.string()).nullable(),
    errorCode: aiErrorCodeSchema.nullable(),
    providerCompletedAt: z.string().datetime({ offset: true }).nullish(),
});

export const aiProviderBudgetSchema = z.object({
    observed_at: z.coerce.date(),
    window_started_at: z.coerce.date(),
    requests: z.number().int(),
    starts_day: z.string(),
    starts: z.number().int(),
    remaining: z.number().int().nullable(),
    reset_at: z.coerce.date().nullable(),
    blocked_until: z.coerce.date().nullable(),
});

export const aiAdmissionCountsSchema = z.object({
    observed_at: z.coerce.date(),
    minute_count: z.number().int(),
    day_count: z.number().int(),
    first_minute_start: z.coerce.date().nullable(),
    unresolved_count: z.number().int(),
    user_unresolved_id: z.string().uuid().nullable(),
});

export const aiCallerWindowSchema = z.object({
    calls: z.number().int(),
    retry_after_seconds: z.number().int(),
});

export type AiAdmissionLimits = z.infer<typeof aiAdmissionLimitsSchema>;
export type AiRequestReservation = z.infer<typeof aiRequestReservationSchema>;
export type AiRequestRecord = z.infer<typeof aiRequestRecordSchema>;
export type AiRequestUpdate = z.infer<typeof aiRequestUpdateSchema>;
export type AiPollRecord = z.infer<typeof aiPollRecordSchema>;
export type AiProviderBudget = z.infer<typeof aiProviderBudgetSchema>;
export type AiAdmissionCounts = z.infer<typeof aiAdmissionCountsSchema>;
export type AiCallerWindow = z.infer<typeof aiCallerWindowSchema>;

export type AiReservation =
    | { request: AiRequestRecord; shouldStart: false }
    | { request: AiRequestRecord; shouldStart: true; portraits: string[] };
