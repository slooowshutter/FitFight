import { NextResponse } from "next/server";
import { ZodError } from "zod";
import { randomUUID } from "node:crypto";
import { ERROR_CODES, type ErrorCode } from "@/lib/types/http/error";
import { recordApiFailure } from "@/lib/observability/server-error-log";
import type { AiErrorContext } from "@/lib/types/ai/error";
import {
    requestTraceIdSchema,
    type RequestOperation,
    type RequestTiming,
    type RequestTimingPhase,
} from "@/lib/types/observability/request-timing";

export { ERROR_CODES } from "@/lib/types/http/error";
export type { ErrorCode } from "@/lib/types/http/error";

export class ApiError extends Error {
    readonly status: number;
    readonly code: ErrorCode;
    readonly detail: unknown;
    readonly clientContext: AiErrorContext;

    constructor(
        status: number,
        code: ErrorCode,
        message: string,
        detail?: unknown,
        clientContext: AiErrorContext = {},
    ) {
        super(message);
        this.name = "ApiError";
        this.status = status;
        this.code = code;
        this.detail = detail;
        this.clientContext = clientContext;
    }
}

export function corsHeaders(request: Request): Headers {
    const headers = new Headers();
    const requestOrigin = request.headers.get("origin");
    const allowed = process.env.FITFIGHT_APP_URL?.replace(/\/$/, "");

    if (requestOrigin && allowed) {
        const ok =
            requestOrigin === allowed ||
            requestOrigin.startsWith("fitfight://") ||
            requestOrigin.startsWith("capacitor://");
        headers.set(
            "Access-Control-Allow-Origin",
            ok ? requestOrigin : allowed,
        );
    } else if (requestOrigin) {
        headers.set("Access-Control-Allow-Origin", requestOrigin);
    } else {
        headers.set("Access-Control-Allow-Origin", "*");
    }

    headers.set(
        "Access-Control-Allow-Methods",
        "GET, POST, PATCH, DELETE, OPTIONS",
    );
    headers.set(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type, Idempotency-Key, X-FitFight-Trace-ID, X-FitFight-Version, X-FitFight-Build",
    );
    headers.set(
        "Access-Control-Expose-Headers",
        "Server-Timing, X-FitFight-Trace-ID, Retry-After",
    );
    headers.set("Access-Control-Max-Age", "86400");
    headers.set("Vary", "Origin");
    headers.set("Cache-Control", "no-store");
    return headers;
}

export function applyCors(request: Request, response: Response): NextResponse {
    const next = new NextResponse(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
    });
    corsHeaders(request).forEach((value, key) => {
        next.headers.set(key, value);
    });
    return next;
}

export function json(body: unknown, status = 200): NextResponse {
    return NextResponse.json(body, { status });
}

export function jsonError(
    error: string,
    code: ErrorCode,
    status: number,
): NextResponse {
    return NextResponse.json({ error, code }, { status });
}

export function corsPreflight(request: Request): NextResponse {
    return new NextResponse(null, {
        status: 204,
        headers: corsHeaders(request),
    });
}

export async function readJson(
    request: Request,
    maxBytes = 1_000_000,
): Promise<unknown> {
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
        throw new ApiError(
            413,
            ERROR_CODES.payload_too_large,
            "Request body is too large",
        );
    }
    const text = await request.text();
    if (new TextEncoder().encode(text).byteLength > maxBytes) {
        throw new ApiError(
            413,
            ERROR_CODES.payload_too_large,
            "Request body is too large",
        );
    }
    if (!text.trim()) {
        return {};
    }
    try {
        return JSON.parse(text) as unknown;
    } catch {
        throw new ApiError(
            400,
            ERROR_CODES.invalid_json,
            "Request body is not valid JSON",
        );
    }
}

export function errorResponse(error: unknown): NextResponse {
    if (error instanceof ApiError) {
        const context = error.clientContext;
        const response = NextResponse.json(
            {
                error: error.message,
                code: error.code,
                request_id: context.request_id,
                retry_after_seconds: context.retry_after_seconds,
            },
            { status: error.status },
        );
        if (context.retry_after_seconds !== undefined) {
            response.headers.set(
                "Retry-After",
                String(context.retry_after_seconds),
            );
        }
        return response;
    }
    if (error instanceof ZodError) {
        const first = error.issues[0];
        const path = first?.path?.join(".") ?? "";
        const message = path
            ? `${path}: ${first.message}`
            : (first?.message ?? "Invalid request");
        return jsonError(message, ERROR_CODES.validation, 400);
    }
    console.error("api_error", error instanceof Error ? error.name : "unknown");
    return jsonError("Internal error", ERROR_CODES.internal, 500);
}

export async function measureRequestStage<T>(
    timing: RequestTiming,
    phase: RequestTimingPhase,
    operation: () => Promise<T>,
): Promise<T> {
    const started = performance.now();
    try {
        return await operation();
    } finally {
        timing.phases[phase] =
            (timing.phases[phase] ?? 0) + performance.now() - started;
    }
}

export function apiRoute<
    P extends Record<string, string> = Record<string, never>,
>(
    handler: (
        request: Request,
        context: { params: P; timing: RequestTiming },
    ) => Promise<Response>,
    operation?: RequestOperation,
) {
    return async (request: Request, context: { params: Promise<P> }) => {
        const started = performance.now();
        const timing: RequestTiming = { phases: {} };
        let response: Response;
        let params = {} as P;
        let caught: unknown;
        try {
            params = await context.params;
            response = await handler(request, { params, timing });
        } catch (error) {
            caught = error;
            response = errorResponse(error);
        }
        if (caught !== undefined) {
            await recordApiFailure(request, caught, {
                params,
                status: response.status,
            });
        }
        if (operation) {
            const parsedTrace = requestTraceIdSchema.safeParse(
                request.headers.get("x-fitfight-trace-id"),
            );
            const traceId = parsedTrace.success
                ? parsedTrace.data
                : randomUUID();
            const durations = {
                ...timing.phases,
                total: performance.now() - started,
            };
            response.headers.set("X-FitFight-Trace-ID", traceId);
            response.headers.set(
                "Server-Timing",
                Object.entries(durations)
                    .map(
                        ([phase, duration]) =>
                            `${phase};dur=${duration.toFixed(1)}`,
                    )
                    .join(", "),
            );
            console.info(
                "fitfight_request",
                JSON.stringify({
                    operation,
                    trace_id: traceId,
                    status: response.status,
                    durations_ms: Object.fromEntries(
                        Object.entries(durations).map(([phase, duration]) => [
                            phase,
                            Math.round(duration * 10) / 10,
                        ]),
                    ),
                }),
            );
        }
        return applyCors(request, response);
    };
}

export function requireUuid(value: string, name: string): string {
    if (
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
            value,
        )
    ) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            `${name} must be a UUID v4`,
        );
    }
    return value;
}
