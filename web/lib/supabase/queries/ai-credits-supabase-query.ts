import type { Sql, TransactionSql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    aiAllowanceSchema,
    aiCreditPricesSchema,
    aiBalanceEventSchema,
    aiCreditBalanceSchema,
    type AiBalanceChange,
    type AiCreditAdjustment,
} from "@/lib/types/ai/credits";

/** The caller's transaction must also commit the associated request transition. */
export async function appendAiBalanceEvent(
    sql: TransactionSql,
    change: AiBalanceChange,
) {
    await sql`select pg_advisory_xact_lock(hashtextextended(${change.operation_key}, 1))`;
    await sql`insert into private.ai_credit_balances (user_id) values (${change.user_id}) on conflict do nothing`;
    const [rawBalance] =
        await sql`select * from private.ai_credit_balances where user_id = ${change.user_id} for update`;
    const balance = aiCreditBalanceSchema.parse(rawBalance);
    const [existing] =
        await sql`select * from private.ai_balance_events where operation_key = ${change.operation_key}`;
    if (existing) {
        const event = aiBalanceEventSchema.parse(existing);
        if (
            Object.entries(change).some(
                ([key, value]) => Reflect.get(event, key) !== value,
            )
        ) {
            throw new ApiError(
                409,
                "ai_request_conflict",
                "This accounting operation was already used with different values.",
            );
        }
        return event;
    }
    const available = balance.available + change.available_change;
    const reserved = balance.reserved + change.reserved_change;
    if (available < 0 || reserved < 0) {
        throw new ApiError(
            409,
            "ai_insufficient_credits",
            "You do not have enough available credits.",
        );
    }
    const [rawEvent] = await sql`
        insert into private.ai_balance_events (
            user_id, sequence, kind, reason, actor, operation_key, request_id, action_key,
            compensates_event_id, quantity, available_before, available_change, available_after,
            reserved_before, reserved_change, reserved_after
        ) values (
            ${change.user_id}, ${balance.sequence + 1}, ${change.kind}, ${change.reason}, ${change.actor},
            ${change.operation_key}, ${change.request_id}, ${change.action_key}, ${change.compensates_event_id},
            ${change.quantity}, ${balance.available}, ${change.available_change}, ${available},
            ${balance.reserved}, ${change.reserved_change}, ${reserved}
        ) returning *
    `;
    await sql`update private.ai_credit_balances set available = ${available}, reserved = ${reserved},
        sequence = ${balance.sequence + 1}, updated_at = clock_timestamp() where user_id = ${change.user_id}`;
    return aiBalanceEventSchema.parse(rawEvent);
}

/** No balance row means zero credits, never an implicit starter grant. */
export async function readAiAllowance(
    userId: string,
    database: Sql = createDatabaseClient(),
) {
    const [row] = await database`
        select coalesce(b.available, 0) as available, coalesce(b.reserved, 0) as reserved, 1 as avatar_price
        from public.profiles p left join private.ai_credit_balances b on b.user_id = p.user_id
        where p.user_id = ${userId}
    `;
    if (!row)
        throw new ApiError(404, "not_found", "This account is not available.");
    const prices = aiCreditPricesSchema.safeParse({
        fitness_price: process.env.BLEND_FITNESS_CREDIT_PRICE,
        group_photo_price: process.env.BLEND_GROUP_PHOTO_CREDIT_PRICE,
    });
    if (!prices.success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    return aiAllowanceSchema.parse({
        ...row,
        fitness_price: prices.data.fitness_price ?? null,
        group_photo_price: prices.data.group_photo_price ?? null,
    });
}

/** operatorId must be the authenticated, environment-authorized operator, never a body field. */
export async function adjustAiCredits(
    operatorId: string,
    input: AiCreditAdjustment,
    database: Sql = createDatabaseClient(),
) {
    return database.begin(async (sql) => {
        const [user] =
            await sql`select user_id from public.profiles where user_id = ${input.user_id} for key share`;
        if (!user)
            throw new ApiError(
                404,
                "not_found",
                "This account is not available.",
            );
        if (input.kind === "adjustment") {
            const [original] =
                await sql`select id from private.ai_balance_events
                where id = ${input.compensates_event_id} and user_id = ${input.user_id}`;
            if (!original)
                throw new ApiError(
                    404,
                    "not_found",
                    "This balance event is not available.",
                );
        }
        return appendAiBalanceEvent(sql, {
            user_id: input.user_id,
            kind: input.kind,
            reason: input.reason,
            actor: `operator:${operatorId}`,
            operation_key: `operator:${input.operation_key}`,
            request_id: null,
            action_key: null,
            compensates_event_id:
                input.kind === "adjustment" ? input.compensates_event_id : null,
            quantity:
                input.kind === "grant"
                    ? input.quantity
                    : Math.abs(input.change),
            available_change:
                input.kind === "grant" ? input.quantity : input.change,
            reserved_change: 0,
        });
    });
}
