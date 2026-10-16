import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import type { CompanionLinesBatch } from "@/lib/types/ai/custom-character";
import { dueCompanionLines, prepareCompanionLines } from "./custom-characters-supabase-query";

const ownerId = "11111111-1111-4111-8111-111111111111";
const purchaseId = "22222222-2222-4222-8222-222222222222";
const attemptId = "33333333-3333-4333-8333-333333333333";
const firstKey = "44444444-4444-4444-8444-444444444444";
const avatarId = "55555555-5555-4555-8555-555555555555";
const options = [1, 2, 3, 4].map((index) => ({ name: `Max ${index}`, line: "Walks like rent is due." }));

function databaseStub(answer: (text: string) => unknown[]) {
    const queries: { text: string; values: unknown[] }[] = [];
    const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const text = strings.join("?").replace(/\s+/g, " ").trim();
        queries.push({ text, values });
        return Promise.resolve(answer(text));
    }) as unknown as Sql;
    Object.assign(sql, { begin: async (callback: (transaction: Sql) => Promise<unknown>) => callback(sql) });
    return { database: sql, queries };
}

function charactersDatabase(linesActionKey: string | null, batches: CompanionLinesBatch[], locale: "en" | "fr" | null = "fr") {
    return databaseStub((text) => {
        if (text.startsWith("select purchase.* from private.custom_character_purchases"))
            return [{
                id: purchaseId,
                account_id: ownerId,
                environment: "Production",
                transaction_id: null,
                original_transaction_id: null,
                description: "A pigeon in a hoodie",
                avatar_action_key: avatarId,
                fitness_action_key: null,
                revoked_at: null,
                signed_at: null,
                purchase_at: null,
                free_claim_key: null,
                portraits_notified_at: null,
                poses_notified_at: null,
                name: null,
                line: null,
                lines_action_key: linesActionKey,
            }];
        if (text.includes("workflow = 'companion_lines'")) return batches;
        if (text.includes("request.workflow = 'avatar'")) return [{ id: avatarId }];
        if (text.includes("from private.device_installations"))
            return locale === null ? [] : [{ id: ownerId, apns_environment: "production", locale }];
        return [];
    });
}

function batch(key: string, status: CompanionLinesBatch["status"]): CompanionLinesBatch {
    return {
        id: key,
        resource_id: purchaseId,
        idempotency_key: key,
        status,
        result: status === "completed" ? { options } : null,
    };
}

function keyUpdates(queries: { text: string; values: unknown[] }[]) {
    return queries.filter((query) => query.text.includes("set lines_action_key")).map((query) => query.values[0]);
}

test("Four more before any first batch is the first batch, under the attempt's own key", async () => {
    const { database, queries } = charactersDatabase(null, []);
    assert.deepEqual(await prepareCompanionLines(ownerId, purchaseId, attemptId, database), {
        kind: "start",
        key: attemptId,
        description: "A pigeon in a hoodie",
        avatarRequestId: avatarId,
        locale: "fr",
        avoid: [],
    });
    // Saved as the first-batch key, so the app and the reconciler do not start another first batch.
    assert.deepEqual(keyUpdates(queries), [attemptId]);
    const repeated = charactersDatabase(attemptId, [batch(attemptId, "running")]);
    assert.deepEqual(await prepareCompanionLines(ownerId, purchaseId, attemptId, repeated.database), { kind: "none" });
    assert.deepEqual(await prepareCompanionLines(ownerId, purchaseId, null, repeated.database), {
        kind: "pending",
        requestId: attemptId,
    });
});

test("Four more after a failed first batch starts with its attempt key and keeps the first-batch key", async () => {
    const { database, queries } = charactersDatabase(firstKey, [batch(firstKey, "failed")], null);
    const step = await prepareCompanionLines(ownerId, purchaseId, attemptId, database);
    assert.equal(step.kind === "start" && step.key, attemptId);
    assert.equal(step.kind === "start" && step.locale, null);
    assert.deepEqual(keyUpdates(queries), []);
});

test("the automatic first batch starts once, and never after any batch exists", async () => {
    const fresh = charactersDatabase(null, []);
    const step = await prepareCompanionLines(ownerId, purchaseId, null, fresh.database);
    assert.ok(step.kind === "start");
    assert.deepEqual(keyUpdates(fresh.queries), [step.key]);
    const saved = charactersDatabase(firstKey, []);
    const again = await prepareCompanionLines(ownerId, purchaseId, null, saved.database);
    assert.equal(again.kind === "start" && again.key, firstKey);
    assert.deepEqual(keyUpdates(saved.queries), []);
    // A user batch that failed or completed leaves the rest to Four more: no unasked batch spends an extra.
    for (const status of ["failed", "completed"] as const) {
        const { database } = charactersDatabase(firstKey, [batch(attemptId, status)]);
        assert.deepEqual(await prepareCompanionLines(ownerId, purchaseId, null, database), { kind: "none" });
    }
});

test("the backfill starts one oldest first batch per run, only while Blend is quiet, and never touches updated_at", async () => {
    const { database, queries } = databaseStub(() => [{ id: purchaseId, user_id: ownerId }]);
    assert.deepEqual(await dueCompanionLines(database), [{ id: purchaseId, userId: ownerId }]);
    assert.equal(queries.length, 1);
    const [query] = queries;
    assert.ok(query.text.startsWith("select purchase.id, account.user_id"));
    assert.match(query.text, /where status in \('starting', 'pending', 'running', 'start_unconfirmed'\)\) < 10/);
    assert.match(query.text, /request\.resource_id = purchase\.id and request\.workflow = 'companion_lines'\)/);
    assert.match(query.text, /order by purchase\.lines_action_key is not null, purchase\.created_at, purchase\.id limit 1$/);
    assert.doesNotMatch(query.text, /updated_at/);
});
