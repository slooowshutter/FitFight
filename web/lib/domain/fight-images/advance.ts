import sharp from "sharp";
import { readAiWorkflowRun, startAiWorkflow } from "@/lib/ai/runner";
import { fightImageRunners, judgeFightImage, planFightImage } from "@/lib/domain/fight-images/plan";
import { renderReferenceSheet } from "@/lib/domain/fight-images/reference-sheet";
import { readCompanionLabel } from "@/lib/supabase/queries/custom-characters-supabase-query";
import {
    claimNextFightImage,
    enqueueChangedFightImages,
    finishFightImageAttempt,
    readRunningFightImages,
    readUnconvertedFightImages,
    saveFightImageRun,
    saveFightImageWebp,
    uploadFightReferenceSheet,
} from "@/lib/supabase/queries/fight-images-supabase-query";
import type { CompanionLabelRow } from "@/lib/types/ai/custom-character";
import { aiImageUrlSchema } from "@/lib/types/ai/workflow";
import { blendOutputSchema } from "@/lib/types/blend/workflow";
import { fightImageConfiguration, fightImageOutputSchema, type FightImageJobRow } from "@/lib/types/fight-images/fight-image";

const TRAIL_SCENE =
    "The runners jog together along the trail from left to right, relaxed and happy, some chatting, one or two pushing a little harder.";

export const fightImageDependencies = {
    enqueue: enqueueChangedFightImages,
    claim: claimNextFightImage,
    running: readRunningFightImages,
    save: saveFightImageRun,
    finish: finishFightImageAttempt,
    upload: uploadFightReferenceSheet,
    render: renderReferenceSheet,
    label: readCompanionLabel,
    unconverted: readUnconvertedFightImages,
    saveWebp: saveFightImageWebp,
    toWebp: async (pngUrl: string) => {
        const response = await fetch(pngUrl, { signal: AbortSignal.timeout(15_000) });
        if (!response.ok) throw new Error(`image ${response.status}`);
        // 1200 px fills a phone at 3x; quality 90 looks the same as the PNG at about a ninth of the size.
        return sharp(Buffer.from(await response.arrayBuffer())).resize({ width: 1200, withoutEnlargement: true }).webp({ quality: 90 }).toBuffer();
    },
    start: (workflowId: string, inputs: Record<string, unknown>) => startAiWorkflow({ workflowId }, inputs),
    read: (workflowId: string, runId: string) => readAiWorkflowRun({ workflowId, runId }),
    now: () => Date.now(),
};

/**
 * One pass of fight group images, run by the reconcile cron: open images for fights whose runners changed,
 * settle finished runs (checking every runner is drawn and faces right, retrying up to three times),
 * copy ready images to WebP, then start due images while time is left. Stops at deadline (a performance.now() value).
 */
export async function advanceFightGroupImages(deadline: number, deps = fightImageDependencies) {
    const summary = { queued: 0, ready: 0, retried: 0, failed: 0, converted: 0, started: 0 };
    for (const job of await deps.running()) {
        if (performance.now() >= deadline) return summary;
        const outcome = await settleRun(job, deps);
        if (outcome) summary[outcome]++;
    }
    // Before new starts, so an image that just became ready is served as WebP within this pass.
    // ponytail: shares the start budget; a large backfill delays starts a few passes, cap it per pass if that matters.
    for (const source of await deps.unconverted()) {
        if (performance.now() >= deadline - 20_000) break;
        try {
            await deps.saveWebp(source.id, await deps.toWebp(source.image_url));
            summary.converted++;
        } catch (error) {
            // The PNG stays the served image and the next pass tries again; one bad image must not stop the rest.
            console.error("fight image webp failed", source.id, error);
        }
    }
    if (!fightImageConfiguration.enabled) return summary;
    summary.queued = await deps.enqueue();

    // NOTE: one start renders and uploads a sheet, then starts a run (up to ~15 s); leave room for maxDuration.
    while (performance.now() < deadline - 20_000) {
        const claimed = await deps.claim();
        if (!claimed) break;
        const { job, cast } = claimed;
        try {
            const names = new Map<string, string>();
            for (const row of cast) {
                if (row.companion_id !== "custom" || !row.companion_image_url) continue;
                const label: Partial<CompanionLabelRow> = await deps.label(row.user_id, row.companion_image_url);
                if (label.companion_name) names.set(row.user_id, label.companion_name);
            }
            const runners = fightImageRunners(cast, names);
            const plan = planFightImage(runners);
            const sheetUrl = await deps.upload(job.id, 0, await deps.render(plan.sheet));
            const workflowId =
                plan.layout === "trail"
                    ? fightImageConfiguration.trail.workflowId
                    : fightImageConfiguration.raceStart.workflowId;
            const inputs =
                plan.layout === "trail"
                    ? { portraits: [sheetUrl], cast_roster: plan.roster, scene: TRAIL_SCENE }
                    : {
                          portraits: [sheetUrl],
                          cast_roster: plan.roster,
                          crowd_size: String(plan.crowdSize),
                          crowd_companions: plan.crowdCompanions,
                      };
            const started = await deps.start(workflowId, inputs);
            await deps.save(job.id, { layout: plan.layout, runners, workflowId, inputs, runId: started.data.runId });
            summary.started++;
        } catch (error) {
            // One fight that cannot start must not hold the others; it fails, keeps its previous image and queues again.
            await deps.finish(job.id, {
                runId: null,
                imageUrl: null,
                check: null,
                problems: [`start failed: ${error instanceof Error ? error.message : String(error)}`.slice(0, 500)],
                pass: false,
                requeue: true,
            });
            summary.failed++;
        }
    }
    return summary;
}

async function settleRun(
    job: FightImageJobRow,
    deps: typeof fightImageDependencies,
): Promise<"ready" | "retried" | "failed" | null> {
    const stale = deps.now() - job.updated_at.getTime() > fightImageConfiguration.runTimeoutMinutes * 60_000;
    if (!job.run_id || !job.workflow_id || !job.inputs || !job.layout || !job.runners) {
        // The start was interrupted before a run was confirmed; give it the timeout to finish recording.
        if (!stale) return null;
        await deps.finish(job.id, {
            runId: null,
            imageUrl: null,
            check: null,
            problems: ["start interrupted"],
            pass: false,
            requeue: true,
        });
        return "failed";
    }
    // An unreadable run (provider down, bad output) waits like an unfinished one instead of stopping every other image.
    const run = await deps.read(job.workflow_id, job.run_id).then(
        (result) => result.data,
        () => null,
    );
    let imageUrl: string | null = null;
    let check: string | null = null;
    let problems: string[];
    if (!run || run.status === "pending" || run.status === "running") {
        if (!stale) return null;
        problems = [run ? "run timed out" : "run unreadable"];
    } else if (run.status !== "completed") {
        problems = [`run ${run.status}`];
    } else {
        // A FitFight workflow returns { image_url, check }; a Blend run, started before 20 Oct 2026, labelled items.
        const own = fightImageOutputSchema.safeParse(run.output);
        const blend = blendOutputSchema.safeParse(run.output);
        const image = blend.success ? blend.data.group_photo?.[0]?.parts.find((part) => part.type === "image") : undefined;
        const text = blend.success ? blend.data.count_check?.[0]?.parts.find((part) => part.type === "text") : undefined;
        const url = own.success ? own.data.image_url : image && "url" in image ? image.url : null;
        imageUrl = url !== null && aiImageUrlSchema.safeParse(url).success ? url : null;
        check = own.success ? own.data.check : text && "text" in text ? text.text : null;
        const expected = planFightImage(job.runners).expected;
        problems = imageUrl ? judgeFightImage(job.layout, expected, check ?? "").problems : ["no image in the result"];
    }
    const pass = problems.length === 0;
    let nextRunId: string | null = null;
    if (!pass && job.attempts < fightImageConfiguration.maxAttempts) {
        try {
            nextRunId = (await deps.start(job.workflow_id, job.inputs)).data.runId;
        } catch {
            // Without a confirmed new run the image fails; the next change of runners opens a fresh one.
            nextRunId = null;
        }
    }
    await deps.finish(job.id, { runId: job.run_id, imageUrl, check, problems, pass, nextRunId });
    return pass ? "ready" : nextRunId ? "retried" : "failed";
}
