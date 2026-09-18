import { randomUUID } from "node:crypto";
import type { Sql, TransactionSql } from "postgres";
import type { ZodType } from "zod";
import { ApiError } from "@/lib/http";
import { aiAvatarResultSchema } from "@/lib/types/ai/workflow";
import { appendAiBalanceEvent } from "@/lib/supabase/queries/ai-credits-supabase-query";
import { signMediaUrl } from "@/lib/supabase/queries/media-supabase-query";
import { aiSourcePortraitSchema } from "@/lib/types/ai/library";
import { aiCreditBalanceSchema, type AiRecovery } from "@/lib/types/ai/credits";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    aiAdmissionCountsSchema,
    aiCallerWindowSchema,
    aiPollRecordSchema,
    aiProviderBudgetSchema,
    aiRequestRecordSchema,
    type AiAdmissionLimits,
    type AiReservation,
    type AiRequestRecord,
    type AiRequestReservation,
    type AiRequestUpdate,
} from "@/lib/types/ai/request";
import type { BlendRateLimit } from "@/lib/types/blend/workflow";

function databaseRow<T>(schema: ZodType<T>, row: unknown): T {
    const parsed = schema.safeParse(row);
    if (!parsed.success) {
        throw new ApiError(
            500,
            "db_error",
            "Could not read the AI request record.",
        );
    }
    return parsed.data;
}

async function countCallerRequest(
    userId: string,
    sql: TransactionSql,
): Promise<ApiError | null> {
    const [raw] = await sql`
        insert into private.ai_caller_windows (user_id, window_started_at, calls)
        values (${userId}, clock_timestamp(), 1)
        on conflict (user_id) do update set
            calls = case when ai_caller_windows.window_started_at <= clock_timestamp() - interval '1 minute'
                then 1 else least(ai_caller_windows.calls + 1, 61) end,
            window_started_at = case when ai_caller_windows.window_started_at <= clock_timestamp() - interval '1 minute'
                then clock_timestamp() else ai_caller_windows.window_started_at end
        returning calls, greatest(1, ceil(extract(epoch from (
            window_started_at + interval '1 minute' - clock_timestamp()
        )))::int) as retry_after_seconds
    `;
    const count = databaseRow(aiCallerWindowSchema, raw);
    return count.calls > 60
        ? new ApiError(
              429,
              "ai_rate_limited",
              "Too many requests. Try again shortly.",
              undefined,
              {
                  retry_after_seconds: count.retry_after_seconds,
              },
          )
        : null;
}

async function reserveProviderRequest(
    sql: TransactionSql,
    limits: AiAdmissionLimits,
    starting: boolean,
): Promise<ApiError | null> {
    await sql`
        update private.ai_provider_budget set
            requests = case when window_started_at <= clock_timestamp() - interval '1 minute' then 0 else requests end,
            window_started_at = case when window_started_at <= clock_timestamp() - interval '1 minute'
                then clock_timestamp() else window_started_at end,
            starts = case when starts_day <> (clock_timestamp() at time zone 'UTC')::date then 0 else starts end,
            starts_day = (clock_timestamp() at time zone 'UTC')::date,
            remaining = case when reset_at <= clock_timestamp() then null else remaining end,
            reset_at = case when reset_at <= clock_timestamp() then null else reset_at end
        where provider = 'blend'
    `;
    const [raw] = await sql`
        select clock_timestamp() as observed_at, window_started_at, requests, starts_day::text, starts, remaining, reset_at, blocked_until
        from private.ai_provider_budget where provider = 'blend'
    `;
    const budget = databaseRow(aiProviderBudgetSchema, raw);
    const now = budget.observed_at.getTime();
    let availableAt = now;
    if (budget.blocked_until !== null)
        availableAt = Math.max(availableAt, budget.blocked_until.getTime());
    if (budget.requests >= limits.providerRequestsPerMinute) {
        availableAt = Math.max(
            availableAt,
            budget.window_started_at.getTime() + 60_000,
        );
    }
    if (budget.remaining === 0 && budget.reset_at !== null) {
        availableAt = Math.max(availableAt, budget.reset_at.getTime());
    }
    if (starting && budget.starts >= limits.globalDailyStarts) {
        availableAt = Math.max(
            availableAt,
            Date.parse(`${budget.starts_day}T00:00:00Z`) + 86_400_000,
        );
    }
    if (availableAt > now) {
        return new ApiError(
            503,
            "ai_busy",
            "AI is busy. Try again later.",
            undefined,
            {
                retry_after_seconds: Math.min(
                    86_400,
                    Math.max(1, Math.ceil((availableAt - now) / 1000)),
                ),
            },
        );
    }
    await sql`
        update private.ai_provider_budget set
            requests = requests + 1,
            starts = starts + ${starting ? 1 : 0},
            remaining = case when remaining is null then null else greatest(0, remaining - 1) end
        where provider = 'blend'
    `;
    return null;
}

/** Authorization for the workflow/resource must precede this atomic paid-work reservation. */
export async function reserveAiRequest(
    userId: string,
    input: AiRequestReservation,
    limits: AiAdmissionLimits | null,
    database: Sql = createDatabaseClient(),
): Promise<AiReservation> {
    const result = await database.begin<AiReservation | ApiError>(
        async (sql) => {
            const callerError = await countCallerRequest(userId, sql);
            if (callerError) return callerError;
            await sql`select pg_advisory_xact_lock(hashtext('fitfight:blend:admission'))`;

            await sql`
            delete from private.ai_requests
            where status in ('completed', 'failed', 'cancelled')
                and updated_at < clock_timestamp() - interval '7 days'
        `;
            await sql`
            update private.ai_requests set status = 'start_unconfirmed', error_code = 'ai_start_unconfirmed', updated_at = clock_timestamp()
            where user_id = ${userId} and idempotency_key = ${input.idempotencyKey}
                and status = 'starting' and lease_expires_at <= clock_timestamp()
        `;
            const [existing] = await sql`
            select * from private.ai_requests
            where user_id = ${userId} and idempotency_key = ${input.idempotencyKey}
        `;
            if (existing) {
                const request = databaseRow(aiRequestRecordSchema, existing);
                if (
                    request.request_hash !== input.requestHash ||
                    request.workflow !== input.workflow ||
                    request.resource_id !== input.resourceId
                ) {
                    return new ApiError(
                        409,
                        "ai_request_conflict",
                        "This request was already used with different parameters.",
                    );
                }
                return { request, shouldStart: false };
            }

            const [pruned] =
                await sql`select request_id from private.ai_balance_events
            where user_id = ${userId} and action_key = ${input.idempotencyKey}`;
            if (pruned)
                return new ApiError(
                    410,
                    "ai_request_expired",
                    "This request has expired. Start a new action to generate again.",
                );
            if (
                input.version === null ||
                input.creditPrice === null ||
                limits === null
            ) {
                return new ApiError(
                    503,
                    "ai_unavailable",
                    "This feature is temporarily unavailable on our side.",
                );
            }

            const [rawCounts] = await sql`
            select
                clock_timestamp() as observed_at,
                count(*) filter (where user_id = ${userId} and created_at >= clock_timestamp() - interval '1 minute')::int as minute_count,
                count(*) filter (where user_id = ${userId} and created_at >= date_trunc('day', clock_timestamp() at time zone 'UTC') at time zone 'UTC')::int as day_count,
                min(created_at) filter (where user_id = ${userId} and created_at >= clock_timestamp() - interval '1 minute') as first_minute_start,
                count(*) filter (where status in ('starting', 'pending', 'running', 'start_unconfirmed'))::int as unresolved_count,
                (array_agg(id) filter (where user_id = ${userId} and status in ('starting', 'pending', 'running', 'start_unconfirmed')))[1] as user_unresolved_id
            from private.ai_requests
            where created_at >= least(date_trunc('day', clock_timestamp() at time zone 'UTC') at time zone 'UTC', clock_timestamp() - interval '1 minute')
                or status in ('starting', 'pending', 'running', 'start_unconfirmed')
        `;
            const counts = databaseRow(aiAdmissionCountsSchema, rawCounts);
            if (counts.user_unresolved_id !== null) {
                return new ApiError(
                    409,
                    "ai_in_progress",
                    "Your previous request is still unresolved. Check its status.",
                    undefined,
                    {
                        request_id: counts.user_unresolved_id,
                    },
                );
            }
            if (
                counts.minute_count >= 3 &&
                counts.first_minute_start !== null
            ) {
                return new ApiError(
                    429,
                    "ai_rate_limited",
                    "You have made a few requests recently. Try again shortly.",
                    undefined,
                    {
                        retry_after_seconds: Math.max(
                            1,
                            Math.ceil(
                                (counts.first_minute_start.getTime() +
                                    60_000 -
                                    counts.observed_at.getTime()) /
                                    1000,
                            ),
                        ),
                    },
                );
            }
            if (counts.day_count >= 20) {
                const now = counts.observed_at;
                const midnight = Date.UTC(
                    now.getUTCFullYear(),
                    now.getUTCMonth(),
                    now.getUTCDate() + 1,
                );
                return new ApiError(
                    429,
                    "ai_daily_limit",
                    "You have reached today's AI limit. It resets at midnight UTC.",
                    undefined,
                    {
                        retry_after_seconds: Math.max(
                            1,
                            Math.ceil((midnight - now.getTime()) / 1000),
                        ),
                    },
                );
            }
            if (counts.unresolved_count >= limits.globalConcurrentRuns) {
                return new ApiError(
                    503,
                    "ai_busy",
                    "AI is busy. Try again later.",
                );
            }
            const portraits: string[] = [];
            if (input.sourceRequestIds.length > 0) {
                const sources = aiSourcePortraitSchema.array().parse(
                    await sql`select wanted.id, request.result, media.object_path
                from unnest(${sql.array(input.sourceRequestIds)}::uuid[]) with ordinality as wanted(id, position)
                left join private.ai_requests as request on request.id = wanted.id
                    and request.user_id = ${userId} and request.workflow = 'avatar' and request.status = 'completed'
                left join private.ai_library_images as library on library.request_id = wanted.id
                    and library.user_id = ${userId} and library.workflow = 'avatar' and library.stage = 'image_url'
                left join public.media_objects as media on media.id = library.media_id
                    and media.owner_id = ${userId} and media.status = 'ready' and media.purpose = 'profile'
                where request.id is not null or media.id is not null
                order by wanted.position`,
                );
                if (sources.length !== input.sourceRequestIds.length) {
                    return new ApiError(
                        404,
                        "not_found",
                        "A source avatar is not available.",
                    );
                }
                for (const source of sources) {
                    if (source.object_path !== null) {
                        const url = await signMediaUrl(source.object_path);
                        if (!url)
                            return new ApiError(
                                503,
                                "storage_error",
                                "Could not read a saved avatar.",
                            );
                        portraits.push(url);
                    } else {
                        portraits.push(
                            databaseRow(aiAvatarResultSchema, source.result)
                                .image_url,
                        );
                    }
                }
            }
            await sql`insert into private.ai_credit_balances (user_id) values (${userId}) on conflict do nothing`;
            const [rawBalance] =
                await sql`select * from private.ai_credit_balances where user_id = ${userId} for update`;
            const balance = aiCreditBalanceSchema.parse(rawBalance);
            const price = input.creditPrice;
            if (balance.available < price) {
                return new ApiError(
                    409,
                    "ai_insufficient_credits",
                    "You do not have enough available credits.",
                );
            }
            const providerError = await reserveProviderRequest(
                sql,
                limits,
                true,
            );
            if (providerError) return providerError;
            const [row] = await sql`
            insert into private.ai_requests (
                user_id, workflow, resource_id, idempotency_key, request_hash, workflow_version,
                lease_token, lease_expires_at, credit_price, credit_state, admitted_at, source_request_ids
            ) values (
                ${userId}, ${input.workflow}, ${input.resourceId}, ${input.idempotencyKey},
                ${input.requestHash}, ${sql.json(input.version)}, ${randomUUID()}, clock_timestamp() + interval '30 seconds',
                ${price}, 'reserved', clock_timestamp(), ${sql.array(input.sourceRequestIds)}::uuid[]
            ) returning *
        `;
            const request = databaseRow(aiRequestRecordSchema, row);
            await appendAiBalanceEvent(sql, {
                user_id: userId,
                kind: "reserve",
                reason: `${input.workflow}_admitted`,
                actor: "server:admission",
                operation_key: `reserve:${request.id}`,
                request_id: request.id,
                action_key: input.idempotencyKey,
                compensates_event_id: null,
                quantity: price,
                available_change: -price,
                reserved_change: price,
            });
            return { request, shouldStart: true, portraits };
        },
    );
    // Return expected rejections from the transaction so their caller limits commit.
    if (result instanceof ApiError) throw result;
    return result;
}

/** Only one server may poll a run at a time; expired starts never permit another POST. */
export async function claimAiRequestPoll(
    userId: string,
    requestId: string,
    limits: AiAdmissionLimits,
    database: Sql = createDatabaseClient(),
    source: "app" | "reconciler" = "app",
): Promise<{ request: AiRequestRecord; shouldPoll: boolean }> {
    const result = await database.begin(async (sql) => {
        if (source === "app") {
            const callerError = await countCallerRequest(userId, sql);
            if (callerError) return callerError;
        }
        await sql`select pg_advisory_xact_lock(hashtext('fitfight:blend:admission'))`;
        await sql`
            update private.ai_requests set status = 'start_unconfirmed', error_code = 'ai_start_unconfirmed', updated_at = clock_timestamp()
            where id = ${requestId} and user_id = ${userId}
                and status = 'starting' and lease_expires_at <= clock_timestamp()
        `;
        const [raw] = await sql`select *, (next_poll_at <= clock_timestamp()
                and (lease_expires_at is null or lease_expires_at <= clock_timestamp())) as poll_due
                from private.ai_requests where id = ${requestId} and user_id = ${userId}`;
        if (!raw)
            return new ApiError(
                404,
                "not_found",
                "This request is not available.",
            );
        const request = databaseRow(aiPollRecordSchema, raw);
        if (
            !["pending", "running"].includes(request.status) ||
            !request.poll_due
        ) {
            return { request, shouldPoll: false };
        }
        const providerError = await reserveProviderRequest(sql, limits, false);
        if (providerError) return providerError;
        const [row] = await sql`
            update private.ai_requests set lease_token = ${randomUUID()},
                lease_expires_at = clock_timestamp() + interval '15 seconds',
                next_poll_at = clock_timestamp() + interval '3 seconds'
            where id = ${requestId} and user_id = ${userId}
                and status in ('pending', 'running') and next_poll_at <= clock_timestamp()
                and (lease_expires_at is null or lease_expires_at <= clock_timestamp())
            returning *
        `;
        return row
            ? {
                  request: databaseRow(aiRequestRecordSchema, row),
                  shouldPoll: true,
              }
            : { request, shouldPoll: false };
    });
    if (result instanceof ApiError) throw result;
    return result;
}

/** A lease token prevents a slow response from overwriting a newer poll or terminal result. */
export async function finishAiRequestAttempt(
    userId: string,
    requestId: string,
    leaseToken: string,
    update: AiRequestUpdate,
    rateLimit: BlendRateLimit,
    database: Sql = createDatabaseClient(),
): Promise<AiRequestRecord | null> {
    return database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtext('fitfight:blend:admission'))`;
        const reset =
            rateLimit.resetAt === undefined
                ? null
                : new Date(rateLimit.resetAt).toISOString();
        const blockedUntil =
            rateLimit.retryAfterSeconds === undefined
                ? null
                : new Date(
                      Date.now() + rateLimit.retryAfterSeconds * 1000,
                  ).toISOString();
        await sql`
            update private.ai_provider_budget set
                remaining = case
                    when ${reset}::timestamptz is null or ${rateLimit.remaining ?? null}::int is null then remaining
                    when reset_at is null or ${reset}::timestamptz > reset_at then ${rateLimit.remaining ?? null}
                    when ${reset}::timestamptz = reset_at then least(remaining, ${rateLimit.remaining ?? null})
                    else remaining end,
                reset_at = greatest(reset_at, ${reset}::timestamptz),
                blocked_until = greatest(blocked_until, ${blockedUntil}::timestamptz)
            where provider = 'blend'
        `;
        const [current] = await sql`select * from private.ai_requests
            where id = ${requestId} and user_id = ${userId} and lease_token = ${leaseToken} for update`;
        if (!current) return null;
        const request = databaseRow(aiRequestRecordSchema, current);
        const terminal = ["completed", "failed", "cancelled"].includes(
            update.status,
        );
        const settles = terminal && request.credit_state === "reserved";
        const creditState = settles
            ? update.status === "completed"
                ? "consumed"
                : "released"
            : request.credit_state;
        if (settles) {
            const consumed = creditState === "consumed";
            await appendAiBalanceEvent(sql, {
                user_id: userId,
                kind: consumed ? "consume" : "release",
                reason: consumed
                    ? `${request.workflow}_completed`
                    : (update.errorCode ?? "ai_failed"),
                actor: "server:settlement",
                operation_key: `settle:${requestId}`,
                request_id: requestId,
                action_key: null,
                compensates_event_id: null,
                quantity: request.credit_price,
                available_change: consumed ? 0 : request.credit_price,
                reserved_change: -request.credit_price,
            });
        }
        const [row] = await sql`
            update private.ai_requests set
                credit_state = ${creditState},
                acknowledged_at = case when ${update.runHandle !== null} then coalesce(acknowledged_at, clock_timestamp()) else acknowledged_at end,
                terminal_observed_at = case when ${terminal} then coalesce(terminal_observed_at, clock_timestamp()) else terminal_observed_at end,
                provider_completed_at = coalesce(provider_completed_at, ${terminal ? (update.providerCompletedAt ?? null) : null}::timestamptz),
                settled_at = case when ${settles} then clock_timestamp() else settled_at end,
                status = ${update.status},
                run_handle = ${update.runHandle === null ? null : sql.json(update.runHandle)},
                result = ${update.result === null ? null : sql.json(update.result)},
                error_code = ${update.errorCode},
                lease_token = null,
                lease_expires_at = null,
                updated_at = clock_timestamp(),
                next_poll_at = greatest(next_poll_at, clock_timestamp() + interval '3 seconds', ${blockedUntil}::timestamptz)
            where id = ${requestId} and user_id = ${userId} and lease_token = ${leaseToken}
            returning *
        `;
        return row ? databaseRow(aiRequestRecordSchema, row) : null;
    });
}

/** Records intent immediately before HTTP submission; it cannot prove provider receipt. */
export async function markAiSubmission(
    userId: string,
    requestId: string,
    leaseToken: string,
    database: Sql = createDatabaseClient(),
) {
    const [row] =
        await database`update private.ai_requests set submission_attempted_at = clock_timestamp()
        where id = ${requestId} and user_id = ${userId} and lease_token = ${leaseToken}
            and status = 'starting' and submission_attempted_at is null and lease_expires_at > clock_timestamp()
        returning id`;
    if (!row)
        throw new ApiError(
            503,
            "ai_start_unconfirmed",
            "We couldn't confirm whether this request started. Check again later.",
            undefined,
            { request_id: requestId },
        );
}

/** Selection does not claim capacity. Each subsequent read must claim the shared poll lease. */
export async function dueAiRequests(database: Sql = createDatabaseClient()) {
    await database`update private.ai_requests set status = 'start_unconfirmed', error_code = 'ai_start_unconfirmed', updated_at = clock_timestamp()
        where status = 'starting' and lease_expires_at <= clock_timestamp()`;
    const rows =
        await database`select * from private.ai_requests where status in ('pending', 'running')
        and next_poll_at <= clock_timestamp() and (lease_expires_at is null or lease_expires_at <= clock_timestamp())
        order by next_poll_at, id limit 4`;
    return rows.map((row) => databaseRow(aiRequestRecordSchema, row));
}

/** Only evidence-based operator decisions may resolve unknown starts; never issues a paid POST. */
export async function recoverAiRequest(
    operatorId: string,
    requestId: string,
    input: AiRecovery,
    database: Sql = createDatabaseClient(),
) {
    return database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtext('fitfight:blend:admission'))`;
        const [raw] =
            await sql`select * from private.ai_requests where id = ${requestId} for update`;
        if (!raw)
            throw new ApiError(
                404,
                "not_found",
                "This request is not available.",
            );
        const request = databaseRow(aiRequestRecordSchema, raw);
        if (request.recovery_operation_key !== null) {
            if (
                request.recovery_operation_key === input.operation_key &&
                request.recovery_actor === operatorId &&
                request.recovery_evidence === input.evidence &&
                (input.action === "attach_run"
                    ? request.run_handle?.runId === input.run_id
                    : request.run_handle === null)
            )
                return request;
            throw new ApiError(
                409,
                "ai_request_conflict",
                "This request already has an operator decision.",
            );
        }
        if (
            request.status !== "start_unconfirmed" ||
            request.run_handle !== null ||
            (request.lease_expires_at !== null &&
                request.lease_expires_at.getTime() > Date.now())
        ) {
            throw new ApiError(
                409,
                "ai_request_conflict",
                "Only an expired, unconfirmed start can be recovered.",
            );
        }
        const release =
            input.action === "confirm_not_accepted" &&
            request.credit_state === "reserved";
        if (release)
            await appendAiBalanceEvent(sql, {
                user_id: request.user_id,
                kind: "release",
                reason: "operator_confirmed_not_accepted",
                actor: `operator:${operatorId}`,
                operation_key: `settle:${requestId}`,
                request_id: requestId,
                action_key: null,
                compensates_event_id: null,
                quantity: request.credit_price,
                available_change: request.credit_price,
                reserved_change: -request.credit_price,
            });
        const [saved] = await sql`update private.ai_requests set
            run_handle = ${input.action === "attach_run" ? sql.json({ ...request.workflow_version, runId: input.run_id }) : null},
            status = ${input.action === "attach_run" ? "pending" : "failed"},
            error_code = ${input.action === "attach_run" ? null : "ai_failed"},
            credit_state = ${release ? "released" : request.credit_state},
            settled_at = case when ${release} then clock_timestamp() else settled_at end,
            acknowledged_at = case when ${input.action === "attach_run"} then clock_timestamp() else acknowledged_at end,
            terminal_observed_at = case when ${input.action === "confirm_not_accepted"} then clock_timestamp() else null end,
            recovery_operation_key = ${input.operation_key}, recovery_actor = ${operatorId}, recovery_evidence = ${input.evidence},
            lease_token = null, lease_expires_at = null, next_poll_at = clock_timestamp(), updated_at = clock_timestamp()
            where id = ${requestId} returning *`;
        return databaseRow(aiRequestRecordSchema, saved);
    });
}
