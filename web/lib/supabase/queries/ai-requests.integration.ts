import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import {
    appendAiBalanceEvent,
    adjustAiCredits,
    readAiAllowance,
} from "./ai-credits-supabase-query";
import { insertAiHttpLogs } from "./ai-http-logs-supabase-query";
import { aiHttpLogSchema } from "@/lib/types/ai/observation";
import { readAiRun } from "@/lib/domain/ai/workflow-requests";
import { reconcileAiRuns } from "@/lib/domain/ai/reconciliation";
import {
    aiCreditBalanceSchema,
    aiBalanceEventSchema,
} from "@/lib/types/ai/credits";
import { ApiError } from "@/lib/http";
import type {
    AiRequestRecord,
    AiRequestReservation,
} from "@/lib/types/ai/request";
import {
    reserveAiRequest,
    claimAiRequestPoll,
    finishAiRequestAttempt,
    markAiSubmission,
    recoverAiRequest,
    dueAiRequests,
} from "./ai-requests-supabase-query";

const databaseURL = process.env.DATABASE_URL;
if (
    process.env.CI !== "true" ||
    !databaseURL ||
    !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)
) {
    throw new Error(
        "These tests require the disposable local database in cloud CI",
    );
}
const database = postgres(databaseURL, { max: 8 });
after(() => database.end());
const version = { workflowId: "test-avatar", versionId: "test-version" };
const limits = {
    globalDailyStarts: 100,
    globalConcurrentRuns: 10,
    providerRequestsPerMinute: 100,
};

function reservation(): AiRequestReservation {
    return {
        workflow: "avatar",
        resourceId: null,
        idempotencyKey: randomUUID(),
        requestHash: "a".repeat(64),
        version,
        creditPrice: 1,
        sourceRequestIds: [],
        description: "Fox",
    };
}

async function failRequest(request: AiRequestRecord) {
    assert.ok(request.lease_token);
    return finishAiRequestAttempt(
        request.user_id,
        request.id,
        request.lease_token,
        {
            status: "failed",
            runHandle: request.run_handle,
            result: null,
            errorCode: "ai_failed",
        },
        {},
        database,
    );
}

test("durable Blend admission and poll leases", async (t) => {
    const users = Array.from({ length: 4 }, () => randomUUID());
    const [owner, other] = users;
    t.after(async () => {
        await database`delete from auth.users where id in ${database(users)}`;
    });
    t.beforeEach(async () => {
        await database`delete from auth.users where id in ${database(users)}`;
        for (const user of users) {
            await database`insert into auth.users (id) values (${user})`;
            await adjustAiCredits(
                owner,
                {
                    kind: "grant",
                    user_id: user,
                    operation_key: randomUUID(),
                    quantity: 50,
                    reason: "test_grant",
                },
                database,
            );
        }
        await database`update private.ai_provider_budget set requests = 0, starts = 0, remaining = null,
            reset_at = null, blocked_until = null, window_started_at = clock_timestamp(),
            starts_day = (clock_timestamp() at time zone 'UTC')::date where provider = 'blend'`;
    });

    t.afterEach(async () => {
        for (const user of users) {
            const [raw] =
                await database`select * from private.ai_credit_balances where user_id = ${user}`;
            const events = (
                await database`select * from private.ai_balance_events where user_id = ${user} order by sequence`
            ).map((row) => aiBalanceEventSchema.parse(row));
            if (!raw) {
                assert.equal(events.length, 0);
                continue;
            }
            const balance = aiCreditBalanceSchema.parse(raw);
            let available = 0;
            let reserved = 0;
            for (const [index, event] of events.entries()) {
                assert.equal(event.sequence, index + 1);
                assert.equal(event.available_before, available);
                assert.equal(event.reserved_before, reserved);
                available += event.available_change;
                reserved += event.reserved_change;
                assert.equal(event.available_after, available);
                assert.equal(event.reserved_after, reserved);
            }
            assert.equal(balance.available, available);
            assert.equal(balance.reserved, reserved);
            assert.equal(balance.sequence, events.length);
            const [holds] =
                await database`select coalesce(sum(credit_price), 0)::int as reserved from private.ai_requests
                where user_id = ${user} and credit_state = 'reserved'`;
            assert.equal(reserved, holds.reserved);
        }
    });

    await t.test(
        "concurrent duplicates reserve exactly one start and one poll, with owner isolation",
        async () => {
            const input = reservation();
            const reservations = await Promise.all(
                Array.from({ length: 8 }, () =>
                    reserveAiRequest(owner, input, limits, database),
                ),
            );
            assert.equal(
                reservations.filter((row) => row.shouldStart).length,
                1,
            );
            assert.equal(
                new Set(reservations.map((row) => row.request.id)).size,
                1,
            );
            const request = reservations[0].request;
            assert.ok(request.lease_token);
            await markAiSubmission(
                owner,
                request.id,
                request.lease_token,
                database,
            );
            await assert.rejects(
                markAiSubmission(
                    owner,
                    request.id,
                    request.lease_token,
                    database,
                ),
            );
            assert.equal(request.credit_price, 1);
            assert.equal(request.credit_state, "reserved");
            assert.ok(request.admitted_at);
            assert.deepEqual(await readAiAllowance(owner, database), {
                available: 49,
                reserved: 1,
                avatar_price: 1,
                fitness_price: null,
                group_photo_price: null,
            });
            await assert.rejects(
                reserveAiRequest(
                    owner,
                    { ...input, requestHash: "b".repeat(64) },
                    limits,
                    database,
                ),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_request_conflict",
            );
            await assert.rejects(
                claimAiRequestPoll(other, request.id, limits, database),
                (error: unknown) =>
                    error instanceof ApiError && error.status === 404,
            );
            await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                {
                    status: "pending",
                    runHandle: { ...version, runId: "existing-run" },
                    result: null,
                    errorCode: null,
                },
                {},
                database,
            );
            await database`update private.ai_requests set next_poll_at = clock_timestamp() where id = ${request.id}`;
            const polls = await Promise.all(
                Array.from({ length: 8 }, () =>
                    claimAiRequestPoll(owner, request.id, limits, database),
                ),
            );
            assert.equal(polls.filter((poll) => poll.shouldPoll).length, 1);
            assert.equal(
                await failRequest(request),
                null,
                "The old start lease cannot overwrite a poll",
            );
            const polled = polls.find((poll) => poll.shouldPoll);
            assert.ok(polled);
            const failed = await failRequest(polled.request);
            assert.ok(
                failed?.acknowledged_at &&
                    failed.submission_attempted_at &&
                    failed.terminal_observed_at &&
                    failed.settled_at,
            );
            assert.equal(failed.credit_state, "released");
            assert.equal(
                (await claimAiRequestPoll(owner, request.id, limits, database))
                    .shouldPoll,
                false,
            );
            const [budget] =
                await database`select starts, requests from private.ai_provider_budget where provider = 'blend'`;
            assert.equal(budget.starts, 1);
            assert.equal(budget.requests, 2);
        },
    );

    await t.test(
        "expired start remains unresolved, accepts a late acknowledgement, and cannot be restarted",
        async () => {
            const input = reservation();
            const { request } = await reserveAiRequest(
                owner,
                input,
                limits,
                database,
            );
            await database`update private.ai_requests set lease_expires_at = clock_timestamp() - interval '1 second' where id = ${request.id}`;
            const duplicate = await reserveAiRequest(
                owner,
                input,
                limits,
                database,
            );
            assert.equal(duplicate.request.status, "start_unconfirmed");
            assert.equal(duplicate.shouldStart, false);
            await assert.rejects(
                reserveAiRequest(owner, reservation(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_in_progress" &&
                    error.clientContext.request_id === request.id,
            );
            assert.ok(request.lease_token);
            const accepted = await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                {
                    status: "pending",
                    runHandle: { ...version, runId: "late-run" },
                    result: null,
                    errorCode: null,
                },
                {},
                database,
            );
            assert.equal(accepted?.status, "pending");
        },
    );

    await t.test(
        "global concurrency and daily budgets persist across different users",
        async () => {
            const capped = {
                ...limits,
                globalConcurrentRuns: 1,
                globalDailyStarts: 1,
            };
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                capped,
                database,
            );
            await assert.rejects(
                reserveAiRequest(other, reservation(), capped, database),
                (error: unknown) =>
                    error instanceof ApiError && error.code === "ai_busy",
            );
            await failRequest(request);
            await assert.rejects(
                reserveAiRequest(other, reservation(), capped, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_busy" &&
                    !!error.clientContext.retry_after_seconds,
            );
        },
    );

    await t.test("provider cooldown blocks both starts and polls", async () => {
        const { request } = await reserveAiRequest(
            owner,
            reservation(),
            limits,
            database,
        );
        assert.ok(request.lease_token);
        await finishAiRequestAttempt(
            owner,
            request.id,
            request.lease_token,
            {
                status: "pending",
                runHandle: { ...version, runId: "limited-run" },
                result: null,
                errorCode: null,
            },
            {
                remaining: 0,
                resetAt: Date.now() + 60_000,
                retryAfterSeconds: 30,
            },
            database,
        );
        await database`update private.ai_requests set next_poll_at = clock_timestamp() where id = ${request.id}`;
        for (const operation of [
            () => reserveAiRequest(other, reservation(), limits, database),
            () => claimAiRequestPoll(owner, request.id, limits, database),
        ]) {
            await assert.rejects(
                operation(),
                (error: unknown) =>
                    error instanceof ApiError && error.code === "ai_busy",
            );
        }
    });

    await t.test(
        "caller and per-user start limits commit rejected attempts",
        async () => {
            for (let index = 0; index < 3; index++) {
                await failRequest(
                    (
                        await reserveAiRequest(
                            owner,
                            reservation(),
                            limits,
                            database,
                        )
                    ).request,
                );
            }
            await assert.rejects(
                reserveAiRequest(owner, reservation(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_rate_limited",
            );
            await database`update private.ai_caller_windows set calls = 60 where user_id = ${owner}`;
            await assert.rejects(
                claimAiRequestPoll(owner, randomUUID(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_rate_limited",
            );
            const [window] =
                await database`select calls from private.ai_caller_windows where user_id = ${owner}`;
            assert.equal(window.calls, 61);
        },
    );

    await t.test(
        "provider request cap covers both starts and reads",
        async () => {
            const capped = { ...limits, providerRequestsPerMinute: 1 };
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                capped,
                database,
            );
            assert.ok(request.lease_token);
            await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                {
                    status: "pending",
                    runHandle: { ...version, runId: "one-request" },
                    result: null,
                    errorCode: null,
                },
                {},
                database,
            );
            await database`update private.ai_requests set next_poll_at = clock_timestamp() where id = ${request.id}`;
            await assert.rejects(
                claimAiRequestPoll(owner, request.id, capped, database),
                (error: unknown) =>
                    error instanceof ApiError && error.code === "ai_busy",
            );
            await assert.rejects(
                reserveAiRequest(other, reservation(), capped, database),
                (error: unknown) =>
                    error instanceof ApiError && error.code === "ai_busy",
            );
        },
    );

    await t.test(
        "twenty starts exhaust the caller's UTC day",
        async (subtest) => {
            const [clock] =
                await database`select extract(epoch from (clock_timestamp() -
            (date_trunc('day', clock_timestamp() at time zone 'UTC') at time zone 'UTC')))::int as day_seconds`;
            if (clock.day_seconds < 60) {
                subtest.skip(
                    "The stricter minute limit takes precedence during the first UTC minute",
                );
                return;
            }
            for (let index = 0; index < 20; index++) {
                await database`insert into private.ai_requests (
                user_id, workflow, idempotency_key, request_hash, workflow_version,
                status, error_code, created_at
            ) values (${owner}, 'avatar', ${randomUUID()}, ${"a".repeat(64)}, ${database.json(version)},
                'failed', 'ai_failed', date_trunc('day', clock_timestamp() at time zone 'UTC') at time zone 'UTC')`;
            }
            await assert.rejects(
                reserveAiRequest(owner, reservation(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_daily_limit",
            );
        },
    );

    await t.test(
        "a late poll cannot overwrite a newer poll lease",
        async () => {
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            assert.ok(request.lease_token);
            await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                {
                    status: "pending",
                    runHandle: { ...version, runId: "slow-poll" },
                    result: null,
                    errorCode: null,
                },
                {},
                database,
            );
            await database`update private.ai_requests set next_poll_at = clock_timestamp() where id = ${request.id}`;
            const first = await claimAiRequestPoll(
                owner,
                request.id,
                limits,
                database,
            );
            assert.equal(first.shouldPoll, true);
            await database`update private.ai_requests set next_poll_at = clock_timestamp(),
            lease_expires_at = clock_timestamp() - interval '1 second' where id = ${request.id}`;
            const second = await claimAiRequestPoll(
                owner,
                request.id,
                limits,
                database,
            );
            assert.equal(second.shouldPoll, true);
            assert.notEqual(
                first.request.lease_token,
                second.request.lease_token,
            );
            assert.equal(await failRequest(first.request), null);
            assert.equal((await failRequest(second.request))?.status, "failed");
        },
    );

    await t.test(
        "terminal retention and account deletion remove only their owned records",
        async () => {
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            await failRequest(request);
            await database`update private.ai_requests set updated_at = clock_timestamp() - interval '8 days' where id = ${request.id}`;
            const unresolved = await reserveAiRequest(
                other,
                reservation(),
                limits,
                database,
            );
            assert.equal(
                (
                    await database`select id from private.ai_requests where id = ${request.id}`
                ).length,
                0,
            );
            await database`delete from auth.users where id = ${other}`;
            assert.equal(
                (
                    await database`select id from private.ai_requests where id = ${unresolved.request.id}`
                ).length,
                0,
            );
            assert.equal(
                (
                    await database`select user_id from private.ai_caller_windows where user_id = ${other}`
                ).length,
                0,
            );
            const [budget] =
                await database`select starts from private.ai_provider_budget where provider = 'blend'`;
            assert.equal(
                budget.starts,
                2,
                "Deleting an account must not refund shared paid-work quota",
            );
        },
    );

    await t.test(
        "zero balances cannot start; allowance reads cannot see another owner",
        async () => {
            await database`delete from auth.users where id = ${owner}`;
            await database`insert into auth.users (id) values (${owner})`;
            assert.deepEqual(await readAiAllowance(owner, database), {
                available: 0,
                reserved: 0,
                avatar_price: 1,
                fitness_price: null,
                group_photo_price: null,
            });
            assert.equal(
                (await readAiAllowance(other, database)).available,
                50,
            );
            await assert.rejects(
                reserveAiRequest(owner, reservation(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_insufficient_credits",
            );
            const [budget] =
                await database`select requests, starts from private.ai_provider_budget where provider = 'blend'`;
            assert.equal(budget.requests, 0);
            assert.equal(budget.starts, 0);
        },
    );

    await t.test(
        "concurrent last-credit actions and repeated settlement cannot overspend",
        async () => {
            await database`delete from auth.users where id = ${owner}`;
            await database`insert into auth.users (id) values (${owner})`;
            const grant = {
                kind: "grant" as const,
                user_id: owner,
                quantity: 1,
                operation_key: randomUUID(),
                reason: "test_grant",
            };
            const grants = await Promise.all(
                Array.from({ length: 8 }, () =>
                    adjustAiCredits(owner, grant, database),
                ),
            );
            assert.equal(new Set(grants.map((event) => event.id)).size, 1);
            await assert.rejects(
                adjustAiCredits(owner, { ...grant, quantity: 2 }, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_request_conflict",
            );
            const attempts = await Promise.allSettled(
                Array.from({ length: 8 }, () =>
                    reserveAiRequest(owner, reservation(), limits, database),
                ),
            );
            const admitted = attempts.filter(
                (result) => result.status === "fulfilled",
            );
            assert.equal(admitted.length, 1);
            for (const result of attempts)
                if (result.status === "rejected") {
                    assert.ok(result.reason instanceof ApiError);
                    assert.equal(result.reason.code, "ai_in_progress");
                }
            const request = admitted[0].value.request;
            assert.ok(request.lease_token);
            const update = {
                status: "completed" as const,
                runHandle: { ...version, runId: "last-credit" },
                result: { image_url: "https://cdn.tryblend.ai/avatar.png" },
                errorCode: null,
                providerCompletedAt: "2026-09-18T00:00:00Z",
            };
            const settlementAttempts = await Promise.allSettled(
                Array.from({ length: 8 }, () =>
                    finishAiRequestAttempt(
                        owner,
                        request.id,
                        request.lease_token!,
                        update,
                        {},
                        database,
                    ),
                ),
            );
            const failedSettlement = settlementAttempts.find(
                (result) => result.status === "rejected",
            );
            if (failedSettlement) throw failedSettlement.reason;
            const settlements = settlementAttempts
                .filter((result) => result.status === "fulfilled")
                .map((result) => result.value);
            assert.equal(settlements.filter(Boolean).length, 1);
            const completed = settlements.find((value) => value !== null);
            assert.equal(
                completed?.provider_completed_at?.toISOString(),
                "2026-09-18T00:00:00.000Z",
            );
            assert.ok(completed?.terminal_observed_at && completed.settled_at);
            assert.equal(completed.credit_state, "consumed");
            assert.deepEqual(await readAiAllowance(owner, database), {
                available: 0,
                reserved: 0,
                avatar_price: 1,
                fitness_price: null,
                group_photo_price: null,
            });
            await assert.rejects(
                reserveAiRequest(owner, reservation(), limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_insufficient_credits",
            );
        },
    );

    await t.test(
        "disabled and missing configuration recover actions without reserving again",
        async () => {
            const input = reservation();
            const { request } = await reserveAiRequest(
                owner,
                input,
                limits,
                database,
            );
            const recovered = await reserveAiRequest(
                owner,
                { ...input, version: null },
                null,
                database,
            );
            assert.equal(recovered.request.id, request.id);
            assert.equal(recovered.shouldStart, false);
            assert.equal(recovered.request.credit_price, 1);
            const changed = await reserveAiRequest(
                owner,
                { ...input, version: { ...version, versionId: "new-version" } },
                limits,
                database,
            );
            assert.deepEqual(changed.request.workflow_version, version);
            await assert.rejects(
                reserveAiRequest(
                    other,
                    { ...reservation(), version: null },
                    null,
                    database,
                ),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_unavailable",
            );
            await assert.rejects(
                reserveAiRequest(
                    owner,
                    { ...input, version: null, requestHash: "c".repeat(64) },
                    null,
                    database,
                ),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_request_conflict",
            );
        },
    );

    await t.test(
        "failed settlement rolls back its event, balance and request; direct tampering is rejected",
        async () => {
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            assert.ok(request.lease_token);
            const before = await readAiAllowance(owner, database);
            await assert.rejects(
                finishAiRequestAttempt(
                    owner,
                    request.id,
                    request.lease_token,
                    {
                        status: "completed",
                        runHandle: { ...version, runId: "rollback" },
                        result: null,
                        errorCode: null,
                    },
                    {},
                    database,
                ),
            );
            assert.deepEqual(await readAiAllowance(owner, database), before);
            const [saved] =
                await database`select status from private.ai_requests where id = ${request.id}`;
            assert.equal(saved.status, "starting");
            assert.equal(
                (
                    await database`select id from private.ai_balance_events where request_id = ${request.id}`
                ).length,
                1,
            );
            await assert.rejects(
                database.begin(async (sql) => {
                    await sql`update private.ai_credit_balances set available = available + 1 where user_id = ${owner}`;
                }),
            );
            assert.deepEqual(await readAiAllowance(owner, database), before);
            await assert.rejects(
                database`update private.ai_balance_events set reason = 'changed' where user_id = ${owner}`,
            );
            await assert.rejects(
                database`delete from private.ai_balance_events where user_id = ${owner}`,
            );
            await assert.rejects(
                database`delete from private.ai_credit_balances where user_id = ${owner}`,
            );
            const [budget] =
                await database`select starts from private.ai_provider_budget where provider = 'blend'`;
            await assert.rejects(
                reserveAiRequest(
                    other,
                    { ...reservation(), requestHash: "invalid" },
                    limits,
                    database,
                ),
            );
            const [afterBudget] =
                await database`select starts from private.ai_provider_budget where provider = 'blend'`;
            assert.equal(afterBudget.starts, budget.starts);
            assert.equal(
                (await readAiAllowance(other, database)).available,
                50,
            );
        },
    );

    await t.test(
        "compensating adjustments preserve the original event and reject invalid chains",
        async () => {
            const [raw] =
                await database`select * from private.ai_balance_events where user_id = ${owner}`;
            const original = aiBalanceEventSchema.parse(raw);
            const adjustment = {
                kind: "adjustment" as const,
                user_id: owner,
                operation_key: randomUUID(),
                change: -2,
                compensates_event_id: original.id,
                reason: "grant_correction",
            };
            const results = await Promise.all(
                Array.from({ length: 4 }, () =>
                    adjustAiCredits(owner, adjustment, database),
                ),
            );
            assert.equal(new Set(results.map((event) => event.id)).size, 1);
            assert.equal(
                (await readAiAllowance(owner, database)).available,
                48,
            );
            const [unchanged] =
                await database`select * from private.ai_balance_events where id = ${original.id}`;
            assert.deepEqual(aiBalanceEventSchema.parse(unchanged), original);
            await assert.rejects(
                adjustAiCredits(
                    owner,
                    {
                        ...adjustment,
                        user_id: other,
                        operation_key: randomUUID(),
                    },
                    database,
                ),
            );
            await assert.rejects(
                database.begin(async (sql) => {
                    await appendAiBalanceEvent(sql, {
                        user_id: owner,
                        kind: "grant",
                        reason: "rollback",
                        actor: "server:test",
                        operation_key: randomUUID(),
                        request_id: null,
                        action_key: null,
                        compensates_event_id: null,
                        quantity: 1,
                        available_change: 1,
                        reserved_change: 0,
                    });
                    await sql`update private.ai_credit_balances set sequence = sequence + 1 where user_id = ${owner}`;
                }),
            );
            assert.equal(
                (await readAiAllowance(owner, database)).available,
                48,
            );
        },
    );

    await t.test(
        "pruning retains all credit events and prevents replay of a retired action",
        async () => {
            const input = reservation();
            const { request } = await reserveAiRequest(
                owner,
                input,
                limits,
                database,
            );
            await failRequest(request);
            await database`update private.ai_requests set updated_at = clock_timestamp() - interval '8 days' where id = ${request.id}`;
            await reserveAiRequest(other, reservation(), limits, database);
            const events =
                await database`select kind from private.ai_balance_events where request_id = ${request.id} order by sequence`;
            assert.deepEqual(
                events.map((event) => event.kind),
                ["reserve", "release"],
            );
            await assert.rejects(
                reserveAiRequest(owner, input, limits, database),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code === "ai_request_expired",
            );
            assert.equal(
                (await readAiAllowance(owner, database)).available,
                50,
            );
        },
    );

    await t.test(
        "unknown starts stay held until an idempotent evidence-based operator recovery",
        async () => {
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            assert.ok(request.lease_token);
            await database`update private.ai_requests set lease_expires_at = clock_timestamp() - interval '1 day' where id = ${request.id}`;
            await dueAiRequests(database);
            assert.equal((await readAiAllowance(owner, database)).reserved, 1);
            const input = {
                action: "confirm_not_accepted" as const,
                operation_key: randomUUID(),
                evidence: "blend-support:case-42",
            };
            await Promise.all(
                Array.from({ length: 4 }, () =>
                    recoverAiRequest(other, request.id, input, database),
                ),
            );
            assert.equal(
                (await readAiAllowance(owner, database)).available,
                50,
            );
            assert.equal((await readAiAllowance(owner, database)).reserved, 0);
            assert.equal(await failRequest(request), null);
            await assert.rejects(
                recoverAiRequest(
                    other,
                    request.id,
                    { ...input, evidence: "changed" },
                    database,
                ),
            );
            const second = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            await database`update private.ai_requests set lease_expires_at = clock_timestamp() - interval '1 second' where id = ${second.request.id}`;
            await dueAiRequests(database);
            const attached = await recoverAiRequest(
                other,
                second.request.id,
                {
                    action: "attach_run",
                    operation_key: randomUUID(),
                    evidence: "blend-history:run-42",
                    run_id: "found-run",
                },
                database,
            );
            assert.equal(attached.status, "pending");
            assert.equal(attached.credit_state, "reserved");
            assert.deepEqual(attached.run_handle, {
                ...version,
                runId: "found-run",
            });
        },
    );

    await t.test(
        "server reconciliation settles abandoned runs despite exhausted caller quota and disabled starts",
        async () => {
            const { request } = await reserveAiRequest(
                owner,
                reservation(),
                limits,
                database,
            );
            assert.ok(request.lease_token);
            await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                {
                    status: "pending",
                    runHandle: { ...version, runId: "abandoned" },
                    result: null,
                    errorCode: null,
                },
                {},
                database,
            );
            await database`update private.ai_requests set next_poll_at = clock_timestamp() where id = ${request.id}`;
            await database`update private.ai_caller_windows set calls = 60 where user_id = ${owner}`;
            const env = {
                BLEND_API_KEY: "bai_test_only",
                BLEND_ENABLED: "false",
                BLEND_AVATAR_WORKFLOW_ID: version.workflowId,
                BLEND_AVATAR_VERSION_ID: version.versionId,
                BLEND_GLOBAL_DAILY_STARTS: "100",
                BLEND_GLOBAL_CONCURRENT_RUNS: "10",
                BLEND_REQUESTS_PER_MINUTE: "100",
            };
            const original = Object.fromEntries(
                Object.keys(env).map((name) => [name, process.env[name]]),
            );
            Object.assign(process.env, env);
            try {
                const result = await reconcileAiRuns({
                    due: () => dueAiRequests(database),
                    pruneLogs: async () => {},
                    read: (user, id, _deps, source) =>
                        readAiRun(
                            user,
                            id,
                            {
                                reserve: async () =>
                                    assert.fail(
                                        "Reconciliation cannot start work",
                                    ),
                                submit: async () =>
                                    assert.fail(
                                        "Reconciliation cannot submit work",
                                    ),
                                start: async () =>
                                    assert.fail(
                                        "Reconciliation cannot call POST",
                                    ),
                                claim: (u, r, l, _db, origin) =>
                                    claimAiRequestPoll(
                                        u,
                                        r,
                                        l,
                                        database,
                                        origin,
                                    ),
                                finish: (u, r, token, update, rate) =>
                                    finishAiRequestAttempt(
                                        u,
                                        r,
                                        token,
                                        update,
                                        rate,
                                        database,
                                    ),
                                read: async () => ({
                                    data: {
                                        id: "abandoned",
                                        status: "completed",
                                        completed_at: "2026-09-18T00:00:00Z",
                                        output: {
                                            avatar: [
                                                {
                                                    id: "image",
                                                    item_index: 0,
                                                    status: "completed",
                                                    parts: [
                                                        {
                                                            type: "image",
                                                            url: "https://cdn.tryblend.ai/avatar.png",
                                                        },
                                                    ],
                                                },
                                            ],
                                        },
                                    },
                                    rateLimit: {},
                                }),
                            },
                            source,
                        ),
                });
                assert.deepEqual(result, { checked: 1, settled: 1 });
                assert.deepEqual(await readAiAllowance(owner, database), {
                    available: 49,
                    reserved: 0,
                    avatar_price: 1,
                    fitness_price: null,
                    group_photo_price: null,
                });
                const [window] =
                    await database`select calls from private.ai_caller_windows where user_id = ${owner}`;
                assert.equal(window.calls, 60);
            } finally {
                for (const [name, value] of Object.entries(original)) {
                    if (value === undefined) delete process.env[name];
                    else process.env[name] = value;
                }
            }
        },
    );

    await t.test(
        "balance event arithmetic and predecessor chains are enforced at commit",
        async () => {
            for (const availableBefore of [0, 50]) {
                await assert.rejects(
                    database.begin(async (sql) => {
                        await sql`insert into private.ai_balance_events (user_id, sequence, kind, reason, actor, operation_key,
                    quantity, available_before, available_change, available_after, reserved_before, reserved_change, reserved_after)
                    values (${owner}, 2, 'grant', 'invalid_history', 'server:test', ${randomUUID()},
                    1, ${availableBefore}, 1, 2, 0, 0, 0)`;
                        await sql`update private.ai_credit_balances set available = 2, sequence = 2 where user_id = ${owner}`;
                    }),
                );
            }
            await assert.rejects(
                database.begin(async (sql) => {
                    await sql`insert into private.ai_balance_events (user_id, sequence, kind, reason, actor, operation_key,
                quantity, available_before, available_change, available_after, reserved_before, reserved_change, reserved_after)
                values (${owner}, 2, 'grant', 'invalid_predecessor', 'server:test', ${randomUUID()},
                1, 0, 1, 1, 0, 0, 0)`;
                    await sql`update private.ai_credit_balances set available = 1, sequence = 2 where user_id = ${owner}`;
                }),
            );
            assert.equal(
                (await readAiAllowance(owner, database)).available,
                50,
            );
        },
    );

    await t.test(
        "HTTP log retention is bounded, and account deletion removes its logs and ledger",
        async () => {
            const entry = aiHttpLogSchema.parse({
                id: randomUUID(),
                observed_at: new Date().toISOString(),
                trace_id: randomUUID(),
                user_id: owner,
                request_id: null,
                leg: "app",
                operation: "allowance",
                workflow_id: null,
                version_id: null,
                run_id: null,
                status: 200,
                elapsed_ms: 3,
                disposition: null,
                outcome: null,
                code: null,
                upstream_code: null,
            });
            await insertAiHttpLogs(
                [
                    {
                        ...entry,
                        id: randomUUID(),
                        observed_at: "2020-01-01T00:00:00.000Z",
                    },
                ],
                database,
            );
            assert.equal(
                (
                    await database`select id from private.ai_http_logs where observed_at < clock_timestamp() - interval '7 days'`
                ).length,
                0,
            );
            await database`insert into private.ai_http_logs (id, observed_at, trace_id, user_id, leg, operation, elapsed_ms)
            select gen_random_uuid(), clock_timestamp() - interval '1 day', ${entry.trace_id}, ${owner}, 'app', 'test_retention', 1
            from generate_series(1, 100000)`;
            await insertAiHttpLogs([entry], database);
            const [count] =
                await database`select count(*)::int as total from private.ai_http_logs`;
            assert.equal(count.total, 100000);
            assert.equal(
                (
                    await database`select id from private.ai_http_logs where id = ${entry.id}`
                ).length,
                1,
            );
            await database`delete from auth.users where id = ${owner}`;
            assert.equal(
                (
                    await database`select id from private.ai_http_logs where user_id = ${owner}`
                ).length,
                0,
            );
            assert.equal(
                (
                    await database`select id from private.ai_balance_events where user_id = ${owner}`
                ).length,
                0,
            );
            assert.equal(
                (
                    await database`select user_id from private.ai_credit_balances where user_id = ${owner}`
                ).length,
                0,
            );
        },
    );

    await t.test(
        "portrait authorization precedes credit reservation, preserves cast order and stores each workflow price",
        async () => {
            const sources = [randomUUID(), randomUUID(), randomUUID()];
            for (const [index, id] of sources.entries()) {
                await database`insert into private.ai_requests (id, user_id, workflow, idempotency_key, request_hash, workflow_version,
                status, run_handle, result, created_at)
                values (${id}, ${index === 2 ? other : owner}, 'avatar', ${randomUUID()}, ${"a".repeat(64)}, ${database.json(version)},
                'completed', ${database.json({ ...version, runId: id })}, ${database.json({ image_url: `https://cdn.tryblend.ai/source-${index}.png` })},
                clock_timestamp() - interval '2 minutes')`;
                await database`insert into private.ai_library_images (request_id, user_id, workflow, description, stage, image_url)
                    values (${id}, ${index === 2 ? other : owner}, 'avatar', 'Fox', 'image_url', ${`https://cdn.tryblend.ai/source-${index}.png`})`;

            }
            for (const ids of [[sources[2]], [randomUUID()]]) {
                await assert.rejects(
                    reserveAiRequest(
                        owner,
                        {
                            ...reservation(),
                            workflow: "fitness",
                            sourceRequestIds: ids,
                            creditPrice: 5,
                        },
                        limits,
                        database,
                    ),
                    (error: unknown) =>
                        error instanceof ApiError && error.status === 404,
                );
                assert.equal(
                    (await readAiAllowance(owner, database)).available,
                    50,
                );
            }
            const [budget] =
                await database`select starts from private.ai_provider_budget where provider = 'blend'`;
            assert.equal(budget.starts, 0);
            const input = {
                ...reservation(),
                workflow: "fitness" as const,
                sourceRequestIds: [sources[0]],
                creditPrice: 5,
            };
            const admitted = await reserveAiRequest(
                owner,
                input,
                limits,
                database,
            );
            assert.equal(admitted.shouldStart, true);
            if (!admitted.shouldStart)
                assert.fail("Expected an admitted fitness request");
            assert.deepEqual(admitted.portraits, [
                "https://cdn.tryblend.ai/source-0.png",
            ]);
            assert.equal(admitted.request.credit_price, 5);
            assert.deepEqual(admitted.request.source_request_ids, [sources[0]]);
            assert.equal((await readAiAllowance(owner, database)).reserved, 5);
            await failRequest(admitted.request);
            const duplicate = await reserveAiRequest(
                owner,
                { ...input, creditPrice: 99 },
                limits,
                database,
            );
            assert.equal(duplicate.request.credit_price, 5);
            assert.equal(duplicate.shouldStart, false);
            const group = await reserveAiRequest(
                owner,
                {
                    ...reservation(),
                    workflow: "group_photo",
                    sourceRequestIds: [sources[1], sources[0]],
                    creditPrice: 2,
                },
                limits,
                database,
            );
            assert.equal(group.shouldStart, true);
            if (!group.shouldStart) assert.fail("Expected a group request");
            assert.deepEqual(group.portraits, [
                "https://cdn.tryblend.ai/source-1.png",
                "https://cdn.tryblend.ai/source-0.png",
            ]);
            assert.equal(group.request.credit_price, 2);
            await failRequest(group.request);
            await database`delete from private.ai_requests where id = ${sources[0]}`;
            assert.equal(
                (await reserveAiRequest(owner, input, limits, database)).request
                    .id,
                admitted.request.id,
            );
        },
    );
});
