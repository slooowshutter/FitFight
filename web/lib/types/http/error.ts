import { z } from "zod";
import { aiErrorCodeSchema } from "@/lib/types/ai/error";

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
    handle_taken: "handle_taken",
    join_code_taken: "join_code_taken",
    companion_taken: "companion_taken",
    special_purchase_required: "special_purchase_required",
    special_limit: "special_limit",
    special_unavailable: "special_unavailable",
    special_account: "special_account",
    special_update_required: "special_update_required",
    character_purchase_required: "character_purchase_required",
    character_account: "character_account",
    character_refunded: "character_refunded",
    character_portrait_chosen: "character_portrait_chosen",
    character_portrait_not_ready: "character_portrait_not_ready",
    character_retry_limit: "character_retry_limit",
    suggestions_limit: "suggestions_limit",
    no_free_characters: "no_free_characters",
    already_member: "already_member",
    fight_not_joinable: "fight_not_joinable",
    fight_full: "fight_full",
    join_rate_limited: "join_rate_limited",
    profile_missing: "profile_missing",
    missing_idempotency_key: "missing_idempotency_key",
    rate_limited: "rate_limited",
    payload_too_large: "payload_too_large",
    archive_too_large: "archive_too_large",
    archive_not_found: "archive_not_found",
    archive_size_mismatch: "archive_size_mismatch",
    archive_checksum_mismatch: "archive_checksum_mismatch",
    archive_invalid: "archive_invalid",
    upload_busy: "upload_busy",
    storage_error: "storage_error",
    db_error: "db_error",
    config: "config",
    release_unavailable: "release_unavailable",
    internal: "internal",
} as const;

export const errorCodeSchema = z.union([
    z.nativeEnum(ERROR_CODES),
    aiErrorCodeSchema,
]);

export type ErrorCode = z.infer<typeof errorCodeSchema>;

/** The body of every `/api/v1` failure (`jsonError` and `errorResponse`). An unknown code still keeps its message. */
export const apiErrorResponseSchema = z.object({
    error: z.string(),
    code: errorCodeSchema.optional().catch(undefined),
});
