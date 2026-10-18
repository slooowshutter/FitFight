import assert from "node:assert/strict";
import { test } from "node:test";
import { advanceFightGroupImages, fightImageDependencies } from "./advance";
import { fightImageRunners } from "./plan";
import { fightImageConfiguration, type FightImageCastRow, type FightImageJobRow } from "@/lib/types/fight-images/fight-image";

const jobId = "33333333-3333-4333-8333-333333333333";
const fightId = "44444444-4444-4444-8444-444444444444";
const image = "https://supabase.tryblend.ai/storage/v1/object/public/generated/a/group.png";
const cast: FightImageCastRow[] = ["badger", "fox"].map((companion, index) => ({
    user_id: `00000000-0000-4000-8000-00000000000${index}`,
    is_owner: index === 0,
    accepted_at: new Date(Date.UTC(2026, 9, 16, 9, index)),
    companion_id: companion,
    companion_image_url: null,
    companion_prompt: null,
}));
const passCheck = '{"total": 2, "counts": [{"name": "Badger", "count": 1}, {"name": "Fox", "count": 1}], "unknown": 0, "facing_left": 0}';
const leftCheck = '{"total": 2, "counts": [{"name": "Badger", "count": 1}, {"name": "Fox", "count": 1}], "unknown": 0, "facing_left": 1}';

function running(attempts: number, updatedAt = new Date()): FightImageJobRow {
    return {
        id: jobId,
        fight_id: fightId,
        status: "running",
        attempts,
        layout: "trail",
        workflow_id: fightImageConfiguration.trail.workflowId,
        run_id: `run-${attempts}`,
        inputs: { cast_roster: "Total characters: 2" },
        runners: fightImageRunners(cast, new Map()),
        updated_at: updatedAt,
    };
}

function completed(check: string) {
    return {
        data: {
            id: "run",
            status: "completed" as const,
            output: {
                group_photo: [{ id: "a", item_index: 0, status: "completed" as const, parts: [{ type: "image" as const, url: image }] }],
                count_check: [{ id: "b", item_index: 0, status: "completed" as const, parts: [{ type: "text" as const, text: check }] }],
            },
        },
        rateLimit: {},
    };
}

function harness(overrides: Partial<typeof fightImageDependencies>) {
    const finished: Parameters<typeof fightImageDependencies.finish>[1][] = [];
    const saved: Parameters<typeof fightImageDependencies.save>[1][] = [];
    const starts: { workflowId: string; inputs: Record<string, unknown> }[] = [];
    const deps: typeof fightImageDependencies = {
        ...fightImageDependencies,
        enqueue: async () => 0,
        claim: async () => null,
        running: async () => [],
        save: async (_id, run) => void saved.push(run),
        finish: async (_id, attempt) => void finished.push(attempt),
        upload: async () => "https://example.supabase.co/storage/v1/object/sign/fight-group-references/sheet-1.png?token=t",
        render: async () => Buffer.from("png"),
        label: async () => ({}),
        unconverted: async () => [],
        saveWebp: async () => {},
        toWebp: async () => Buffer.from("webp"),
        start: async (workflowId, inputs) => {
            starts.push({ workflowId, inputs });
            return { data: { workflowId, runId: `run-new-${starts.length}` }, rateLimit: {} };
        },
        read: async () => completed(passCheck),
        now: () => Date.now(),
        ...overrides,
    };
    return { deps, finished, saved, starts };
}

test("a due image renders one sheet and starts the trail workflow with the roster", async () => {
    let claimed = false;
    const { deps, saved, starts } = harness({
        claim: async () => {
            if (claimed) return null;
            claimed = true;
            return { job: { ...running(1), layout: null, run_id: null, workflow_id: null, inputs: null, runners: null }, cast };
        },
    });
    const summary = await advanceFightGroupImages(performance.now() + 60_000, deps);
    assert.equal(summary.started, 1);
    assert.equal(starts[0].workflowId, fightImageConfiguration.trail.workflowId);
    assert.match(String(starts[0].inputs.cast_roster), /^Total characters: 2\nBadger: /);
    assert.equal(saved[0].layout, "trail");
    assert.equal(saved[0].runId, "run-new-1");
});

test("a passing check makes the image ready", async () => {
    const { deps, finished } = harness({ running: async () => [running(1)] });
    const summary = await advanceFightGroupImages(performance.now() + 60_000, deps);
    assert.equal(summary.ready, 1);
    assert.equal(finished[0].pass, true);
    assert.equal(finished[0].imageUrl, image);
});

test("a runner facing left retries with the same inputs until the third attempt fails", async () => {
    const retry = harness({ running: async () => [running(1)], read: async () => completed(leftCheck) });
    assert.equal((await advanceFightGroupImages(performance.now() + 60_000, retry.deps)).retried, 1);
    assert.deepEqual(retry.starts[0].inputs, { cast_roster: "Total characters: 2" });
    assert.equal(retry.finished[0].nextRunId, "run-new-1");

    const last = harness({ running: async () => [running(fightImageConfiguration.maxAttempts)], read: async () => completed(leftCheck) });
    assert.equal((await advanceFightGroupImages(performance.now() + 60_000, last.deps)).failed, 1);
    assert.equal(last.starts.length, 0);
    assert.deepEqual(last.finished[0].problems, ["facing left: 1"]);
});

test("an unfinished run waits, then counts as a failed attempt after the timeout", async () => {
    const pending = { data: { id: "run", status: "running" as const, output: null }, rateLimit: {} };
    const fresh = harness({ running: async () => [running(1)], read: async () => pending });
    assert.deepEqual(await advanceFightGroupImages(performance.now() + 60_000, fresh.deps), {
        queued: 0, ready: 0, retried: 0, failed: 0, converted: 0, started: 0,
    });
    const old = new Date(Date.now() - (fightImageConfiguration.runTimeoutMinutes + 1) * 60_000);
    const stale = harness({ running: async () => [running(1, old)], read: async () => pending });
    assert.equal((await advanceFightGroupImages(performance.now() + 60_000, stale.deps)).retried, 1);
});

test("an unreadable run waits like an unfinished one and does not stop the other images", async () => {
    const other = { ...running(1), id: "55555555-5555-4555-8555-555555555555", run_id: "run-other" };
    const { deps, finished } = harness({
        running: async () => [running(1), other],
        read: async (_workflowId, runId) => {
            if (runId === "run-1") throw new Error("Blend 502");
            return completed(passCheck);
        },
    });
    const summary = await advanceFightGroupImages(performance.now() + 60_000, deps);
    assert.equal(summary.ready, 1);
    assert.equal(finished.length, 1);
    const old = new Date(Date.now() - (fightImageConfiguration.runTimeoutMinutes + 1) * 60_000);
    const stale = harness({ running: async () => [running(1, old)], read: async () => Promise.reject(new Error("Blend 502")) });
    await advanceFightGroupImages(performance.now() + 60_000, stale.deps);
    assert.deepEqual(stale.finished[0].problems, ["run unreadable"]);
});

test("a start that throws fails that image without stopping the pass", async () => {
    let calls = 0;
    const { deps, finished } = harness({
        claim: async () => (calls++ === 0 ? { job: running(1), cast } : null),
        upload: async () => {
            throw new Error("storage down");
        },
    });
    const summary = await advanceFightGroupImages(performance.now() + 60_000, deps);
    assert.equal(summary.failed, 1);
    assert.match(finished[0].problems[0], /storage down/);
    assert.equal(finished[0].requeue, true, "an infrastructure failure lets the fight queue again");
});

test("ready images get a WebP copy, and one that cannot convert does not stop the others", async () => {
    const broken = { id: "66666666-6666-4666-8666-666666666666", image_url: "https://supabase.tryblend.ai/gone.png" };
    const saved: string[] = [];
    const { deps } = harness({
        unconverted: async () => [broken, { id: jobId, image_url: image }],
        toWebp: async (url) => {
            if (url === broken.image_url) throw new Error("image 404");
            return Buffer.from("webp");
        },
        saveWebp: async (id) => void saved.push(id),
    });
    const summary = await advanceFightGroupImages(performance.now() + 60_000, deps);
    assert.equal(summary.converted, 1);
    assert.deepEqual(saved, [jobId]);
});
