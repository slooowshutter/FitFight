import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import { companionSuggestions } from "./companion-suggestions";
import type { CompanionLinesBatch } from "@/lib/types/ai/custom-character";

const purchaseId = "33333333-3333-4333-8333-333333333333";

function batch(status: CompanionLinesBatch["status"], label = "Max"): CompanionLinesBatch {
    return {
        id: randomUUID(),
        resource_id: purchaseId,
        idempotency_key: randomUUID(),
        status,
        result: status === "completed"
            ? { options: [1, 2, 3, 4].map((index) => ({ name: `${label} ${index}`, line: `Line ${index}` })) }
            : null,
    };
}

test("the first completed batch is free and three extra batches complete or run before the limit", () => {
    assert.deepEqual(companionSuggestions([]), {
        suggestions: [], suggestions_pending: false, more_suggestions_left: 3,
    });
    const first = companionSuggestions([batch("completed")]);
    assert.equal(first.suggestions.length, 4);
    assert.equal(first.more_suggestions_left, 3);
    const twoExtra = [batch("completed"), batch("completed"), batch("completed")];
    assert.equal(companionSuggestions(twoExtra).more_suggestions_left, 1);
    const running = companionSuggestions([...twoExtra, batch("running")]);
    assert.equal(running.suggestions_pending, true);
    assert.equal(running.more_suggestions_left, 0);
    assert.equal(companionSuggestions([...twoExtra, batch("completed")]).more_suggestions_left, 0);
    assert.equal(companionSuggestions([...twoExtra, batch("completed")]).suggestions.length, 16);
});

test("batches before the first completed one are free, so a failed first batch is retried by Four more", () => {
    const retried = [batch("failed"), batch("cancelled"), batch("start_unconfirmed"), batch("completed")];
    assert.deepEqual(companionSuggestions(retried), {
        suggestions: retried[3].result?.options,
        suggestions_pending: false,
        // Three extra are allowed, but only two batch slots of the six remain.
        more_suggestions_left: 2,
    });
    // A Four more batch running before any batch completed is the first one, not an extra.
    assert.equal(companionSuggestions([batch("failed"), batch("running")]).more_suggestions_left, 3);
    // After a completed batch, failed and cancelled batches use none of the three extra, only batch slots.
    const state = companionSuggestions([batch("completed"), batch("failed"), batch("cancelled"), batch("completed")]);
    assert.equal(state.more_suggestions_left, 2);
    assert.equal(state.suggestions.length, 8);
});

test("a starting or pending batch is in progress, and suggestions keep generation order", () => {
    assert.equal(companionSuggestions([batch("starting")]).suggestions_pending, true);
    assert.equal(companionSuggestions([batch("pending")]).suggestions_pending, true);
    const ordered = companionSuggestions([batch("completed", "First"), batch("completed", "Second")]);
    assert.deepEqual(ordered.suggestions.map((option) => option.name), [
        "First 1", "First 2", "First 3", "First 4", "Second 1", "Second 2", "Second 3", "Second 4",
    ]);
    assert.equal(ordered.more_suggestions_left, 2);
});

test("six batches of any status end the suggestions, so failing runs cannot repeat forever", () => {
    const failing = [1, 2, 3, 4, 5, 6].map(() => batch("failed"));
    assert.equal(companionSuggestions(failing).more_suggestions_left, 0);
    assert.equal(companionSuggestions(failing.slice(0, 5)).more_suggestions_left, 1);
    const mixed = [batch("completed"), batch("failed"), batch("failed"), batch("failed"), batch("completed")];
    assert.equal(companionSuggestions(mixed).more_suggestions_left, 1);
});
