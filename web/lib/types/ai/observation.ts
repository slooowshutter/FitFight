import { z } from "zod";
import { aiRequestStateValues } from "@/lib/types/ai/request";
import { errorCodeSchema } from "@/lib/types/http/error";

export const aiHttpLogSchema = z.object({
    id: z.string().uuid(),
    observed_at: z.string().datetime(),
    trace_id: z.string().uuid(),
    user_id: z.string().uuid().nullable(),
    request_id: z.string().uuid().nullable(),
    leg: z.enum(["app", "blend", "reconciler", "operator"]),
    operation: z.string().max(40),
    workflow_id: z.string().max(200).nullable(),
    version_id: z.string().max(200).nullable(),
    run_id: z.string().max(200).nullable(),
    status: z.number().int().min(100).max(599).nullable(),
    elapsed_ms: z.number().int().nonnegative(),
    disposition: z
        .enum(["submitted", "recovered", "observed", "rejected"])
        .nullable(),
    outcome: z.string().max(64).nullable(),
    code: z.string().max(80).nullable(),
    upstream_code: z.string().max(80).nullable(),
});
export const aiResponseObservationSchema = z.object({
    request_id: z.string().uuid().optional(),
    status: z.enum(aiRequestStateValues).optional(),
    code: errorCodeSchema.optional(),
});
export type AiHttpLog = z.infer<typeof aiHttpLogSchema>;
export type AiResponseObservation = z.infer<typeof aiResponseObservationSchema>;
export type AiObservationContext = {
    traceId: string;
    identifiers: Pick<
        AiHttpLog,
        "user_id" | "request_id" | "workflow_id" | "version_id" | "run_id"
    >;
    logs: AiHttpLog[];
    disposition: AiHttpLog["disposition"];
};
export type AiHttpLogWriter = (rows: AiHttpLog[]) => Promise<void>;
