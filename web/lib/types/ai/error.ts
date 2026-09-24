import { z } from "zod";

export const aiErrorCodeValues = [
    "ai_insufficient_credits",
    "ai_request_expired",
    "ai_rate_limited",
    "ai_daily_limit",
    "ai_in_progress",
    "ai_request_conflict",
    "ai_busy",
    "ai_unavailable",
    "ai_failed",
    "ai_invalid_result",
    "ai_status_unavailable",
    "ai_start_unconfirmed",
    "ai_cancelled",
] as const;

export const aiErrorCodeSchema = z.enum(aiErrorCodeValues);

export const aiErrorContextSchema = z.object({
    request_id: z.string().uuid().optional(),
    retry_after_seconds: z.number().int().positive().max(86_400).optional(),
});

export type AiErrorCode = z.infer<typeof aiErrorCodeSchema>;
export type AiErrorContext = z.infer<typeof aiErrorContextSchema>;

export const aiErrorMessages: Record<AiErrorCode, string> = {
    ai_insufficient_credits: "You do not have enough available credits.",
    ai_request_expired:
        "This request has expired. Start a new action to generate again.",
    ai_rate_limited:
        "You have made a few requests recently. Try again shortly.",
    ai_daily_limit:
        "You have reached today's AI limit. It resets at midnight UTC.",
    ai_in_progress:
        "Your previous request is still unresolved. Check its status.",
    ai_request_conflict:
        "This request was already used with different parameters.",
    ai_busy: "AI is busy. Try again later.",
    ai_unavailable: "This feature is temporarily unavailable on our side.",
    ai_failed: "We couldn't complete this request.",
    ai_invalid_result: "We couldn't read the generated result.",
    ai_status_unavailable: "We couldn't check the result. Check again.",
    ai_start_unconfirmed:
        "We couldn't confirm whether this request started. Check again later.",
    ai_cancelled: "This request was cancelled.",
};
