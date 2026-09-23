import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";
import { requestTraceIdSchema } from "@/lib/types/observability/request-timing";
import {
    aiHttpLogSchema,
    aiResponseObservationSchema,
    type AiHttpLog,
    type AiHttpLogWriter,
    type AiObservationContext,
} from "@/lib/types/ai/observation";

const observations = new AsyncLocalStorage<AiObservationContext>();
let writer: AiHttpLogWriter | null = null;

export function setAiHttpLogWriter(next: AiHttpLogWriter | null) {
    writer = next;
}

export function correlateAiRequest(
    identifiers: Partial<AiObservationContext["identifiers"]>,
    disposition?: AiHttpLog["disposition"],
) {
    const context = observations.getStore();
    if (context) {
        Object.assign(context.identifiers, identifiers);
        if (disposition !== undefined) context.disposition = disposition;
    }
}

/** Accepts only bounded diagnostic fields; bodies, prompts and media URLs have no log field. */
export function observeAiCall(
    input: Pick<
        AiHttpLog,
        | "leg"
        | "operation"
        | "status"
        | "elapsed_ms"
        | "code"
        | "upstream_code"
        | "outcome"
    >,
) {
    const context = observations.getStore();
    if (!context || context.logs.length >= 8) return;
    context.logs.push(
        aiHttpLogSchema.parse({
            id: randomUUID(),
            observed_at: new Date().toISOString(),
            trace_id: context.traceId,
            ...context.identifiers,
            disposition: context.disposition,
            ...input,
        }),
    );
}

/** Logs a prepared response, not confirmed receipt by the phone. */
export function observeAiHttp<P extends Record<string, string>>(
    handler: (
        request: Request,
        context: { params: Promise<P> },
    ) => Promise<Response>,
    operation: string,
    leg: "app" | "reconciler" | "operator" = "app",
) {
    return async (request: Request, routeContext: { params: Promise<P> }) => {
        const parsedTrace = requestTraceIdSchema.safeParse(
            request.headers.get("x-fitfight-trace-id"),
        );
        const traceId = parsedTrace.success ? parsedTrace.data : randomUUID();
        const headers = new Headers(request.headers);
        headers.set("X-FitFight-Trace-ID", traceId);
        const tracedRequest = new Request(request, { headers });
        const context: AiObservationContext = {
            traceId,
            logs: [],
            disposition: null,
            identifiers: {
                user_id: null,
                request_id: null,
                workflow_id: null,
                version_id: null,
                run_id: null,
            },
        };
        return observations.run(context, async () => {
            const started = performance.now();
            const response = await handler(tracedRequest, routeContext);
            const elapsed = Math.round(performance.now() - started);
            response.headers.set("X-FitFight-Trace-ID", traceId);
            response.headers.set("Server-Timing", `total;dur=${elapsed}`);
            try {
                const summary = aiResponseObservationSchema.parse(
                    await response.clone().json(),
                );
                const identifiers = {
                    ...context.identifiers,
                    request_id:
                        summary.request_id ?? context.identifiers.request_id,
                };
                context.logs.push(
                    aiHttpLogSchema.parse({
                        id: randomUUID(),
                        observed_at: new Date().toISOString(),
                        trace_id: traceId,
                        ...identifiers,
                        leg,
                        operation,
                        status: response.status,
                        elapsed_ms: elapsed,
                        disposition:
                            response.status >= 400
                                ? "rejected"
                                : context.disposition,
                        outcome: summary.status ?? null,
                        code: summary.code ?? null,
                        upstream_code: null,
                    }),
                );
                if (writer) await writer(context.logs);
                else {
                    const { insertAiHttpLogs } = await import(
                        "@/lib/supabase/queries/ai-http-logs-supabase-query"
                    );
                    await insertAiHttpLogs(context.logs);
                }
            } catch {
                // Diagnostics cannot undo a paid action or turn a saved success into a retry.
                console.error(
                    "fitfight_ai_observation_unavailable",
                    JSON.stringify({ trace_id: traceId, operation }),
                );
            }
            return response;
        });
    };
}
