import type { CompanionLinesBatch } from "@/lib/types/ai/custom-character";

/**
 * Batches come in generation order and run one at a time. A batch is extra when an earlier batch had completed
 * before it started, so a failed first batch is retried for free. At most three extra batches complete or run, and
 * at most six batches of any status exist, because a description written to make every run fail would otherwise
 * buy unlimited paid Blend runs.
 */
export function companionSuggestions(batches: CompanionLinesBatch[]) {
    const running = batches.filter((batch) => ["starting", "pending", "running"].includes(batch.status));
    const firstCompleted = batches.findIndex((batch) => batch.status === "completed");
    const extra = firstCompleted < 0
        ? []
        : batches.slice(firstCompleted + 1).filter((batch) => batch.status === "completed" || running.includes(batch));
    return {
        suggestions: batches.flatMap((batch) => (batch.status === "completed" && batch.result ? batch.result.options : [])),
        suggestions_pending: running.length > 0,
        more_suggestions_left: Math.max(0, Math.min(3 - extra.length, 6 - batches.length)),
    };
}
