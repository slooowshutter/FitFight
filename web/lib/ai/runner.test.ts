import assert from "node:assert/strict";
import { test } from "node:test";
import { startAiWorkflow } from "./runner";

test("a FitFight start without the AI workflows key answers ai_unavailable before anything is paid", async () => {
    const previous = process.env.AI_WORKFLOWS_OPENROUTER_API_KEY;
    delete process.env.AI_WORKFLOWS_OPENROUTER_API_KEY;
    try {
        await assert.rejects(startAiWorkflow({ workflowId: "fitfight:trail" }, { portraits: [] }), { code: "ai_unavailable" });
    } finally {
        if (previous !== undefined) process.env.AI_WORKFLOWS_OPENROUTER_API_KEY = previous;
    }
});

test("a FitFight start with inputs that do not fit its workflow is a bug, not an unconfirmed start", async () => {
    const previous = process.env.AI_WORKFLOWS_OPENROUTER_API_KEY;
    process.env.AI_WORKFLOWS_OPENROUTER_API_KEY = "test-only-key";
    try {
        await assert.rejects(startAiWorkflow({ workflowId: "fitfight:fitness" }, { portraits: [] }), { name: "ZodError" });
        await assert.rejects(startAiWorkflow({ workflowId: "fitfight:unknown" }, {}), { name: "ZodError" });
    } finally {
        if (previous === undefined) delete process.env.AI_WORKFLOWS_OPENROUTER_API_KEY;
        else process.env.AI_WORKFLOWS_OPENROUTER_API_KEY = previous;
    }
});
