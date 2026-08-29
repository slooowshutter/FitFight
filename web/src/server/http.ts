import { NextResponse } from "next/server";
import { ZodError } from "zod";

export const ERROR_CODES = {
  unauthorized: "unauthorized",
  forbidden: "forbidden",
  not_found: "not_found",
  validation: "validation",
  invalid_json: "invalid_json",
  conflict: "conflict",
  invalid_metric: "invalid_metric",
  fight_not_startable: "fight_not_startable",
  fight_not_cancellable: "fight_not_cancellable",
  invite_expired: "invite_expired",
  invite_revoked: "invite_revoked",
  invite_wrong_user: "invite_wrong_user",
  handle_not_found: "handle_not_found",
  already_member: "already_member",
  profile_missing: "profile_missing",
  missing_idempotency_key: "missing_idempotency_key",
  payload_too_large: "payload_too_large",
  db_error: "db_error",
  config: "config",
  internal: "internal",
} as const;

export type ErrorCode = (typeof ERROR_CODES)[keyof typeof ERROR_CODES];

export class ApiError extends Error {
  readonly status: number;
  readonly code: ErrorCode;

  constructor(status: number, code: ErrorCode, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
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
    headers.set("Access-Control-Allow-Origin", ok ? requestOrigin : allowed);
  } else if (requestOrigin) {
    headers.set("Access-Control-Allow-Origin", requestOrigin);
  } else {
    headers.set("Access-Control-Allow-Origin", "*");
  }

  headers.set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  headers.set(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, Idempotency-Key",
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
  return new NextResponse(null, { status: 204, headers: corsHeaders(request) });
}

export async function readJson(request: Request, maxBytes = 1_000_000): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new ApiError(413, ERROR_CODES.payload_too_large, "Request body is too large");
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new ApiError(413, ERROR_CODES.payload_too_large, "Request body is too large");
  }
  if (!text.trim()) {
    return {};
  }
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new ApiError(400, ERROR_CODES.invalid_json, "Request body is not valid JSON");
  }
}

export function errorResponse(error: unknown): NextResponse {
  if (error instanceof ApiError) {
    return jsonError(error.message, error.code, error.status);
  }
  if (error instanceof ZodError) {
    const first = error.issues[0];
    const path = first?.path?.join(".") ?? "";
    const message = path ? `${path}: ${first.message}` : first?.message ?? "Invalid request";
    return jsonError(message, ERROR_CODES.validation, 400);
  }
  console.error("api_error", error instanceof Error ? error.name : "unknown");
  return jsonError("Internal error", ERROR_CODES.internal, 500);
}

export function apiRoute<P extends Record<string, string> = Record<string, never>>(
  handler: (request: Request, context: { params: P }) => Promise<Response>,
) {
  return async (request: Request, context: { params: Promise<P> }) => {
    try {
      const params = await context.params;
      const response = await handler(request, { params });
      return applyCors(request, response);
    } catch (error) {
      return applyCors(request, errorResponse(error));
    }
  };
}

export function requireUuid(value: string, name: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new ApiError(400, ERROR_CODES.validation, `${name} must be a UUID`);
  }
  return value;
}
