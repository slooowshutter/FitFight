import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { insertAppErrorLog } from "@/lib/supabase/queries/app-error-logs-supabase-query";
import { posthogExceptionWebhookSchema } from "@/lib/types/observability/app-error-log";

test("a PostHog exception is copied to the private app error table once", async () => {
    const statements: { text: string; values: unknown[] }[] = [];
    const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        statements.push({ text: strings.join("?"), values });
        return Promise.resolve([{ id: "row" }]);
    }) as unknown as Sql;
    const payload = posthogExceptionWebhookSchema.parse({
        event: {
            uuid: "0199f0a1-2b3c-7d4e-8f90-123456789abc",
            event: "$exception",
            distinct_id: "11111111-1111-4111-8111-111111111111",
            timestamp: "2026-10-15T12:00:00.000Z",
            elements_chain: "",
            url: "https://us.posthog.com/project/658541/events/x",
            properties: {
                environment: "prod",
                $app_version: "1.2.0",
                $app_build: "230",
                $exception_issue_id: "0199f0a1-0000-7000-8000-000000000001",
                $exception_list: [
                    {
                        type: "EXC_BAD_ACCESS",
                        value: "Crash in FightsView",
                        stacktrace: { frames: [] },
                    },
                ],
            },
        },
    });
    assert.equal(await insertAppErrorLog(payload, sql), true);
    assert.equal(statements.length, 1);
    assert.match(
        statements[0]?.text ?? "",
        /insert into private\.app_error_logs/,
    );
    assert.match(
        statements[0]?.text ?? "",
        /on conflict \(posthog_event_id\) do nothing/,
    );
    assert.deepEqual(statements[0]?.values.slice(0, 9), [
        payload.event.uuid,
        "2026-10-15T12:00:00.000Z",
        "prod",
        "11111111-1111-4111-8111-111111111111",
        "1.2.0",
        "230",
        "EXC_BAD_ACCESS",
        "Crash in FightsView",
        "0199f0a1-0000-7000-8000-000000000001",
    ]);
});

test("the webhook accepts only PostHog exceptions", () => {
    const event = {
        uuid: "0199f0a1-2b3c-7d4e-8f90-123456789abc",
        distinct_id: "x",
        timestamp: "2026-10-15T12:00:00Z",
        properties: {},
    };
    assert.equal(
        posthogExceptionWebhookSchema.safeParse({
            event: { ...event, event: "$pageview" },
        }).success,
        false,
    );
    assert.equal(
        posthogExceptionWebhookSchema.safeParse({
            event: { ...event, event: "$exception" },
        }).success,
        true,
    );
});
