import { startAiRun, readAiRun } from "@/lib/domain/ai/workflow-requests";
import { ApiError } from "@/lib/http";
import { sendUserAlert } from "@/lib/notifications/send-user-alert";
import {
    chooseCustomCharacterPortrait,
    claimCustomCharacterPush,
    prepareCompanionLines,
    prepareCustomCharacterStage,
    readCustomCharacterStore,
} from "@/lib/supabase/queries/custom-characters-supabase-query";
import type { CustomCharacterAdvanceRequest } from "@/lib/types/ai/custom-character";

/** Start rejections that the per-minute reconciler retries on its own. */
export const deferredCharacterStartCodes = ["ai_busy", "ai_unavailable", "ai_rate_limited", "ai_daily_limit", "ai_in_progress"];

/**
 * A purchase keeps one description unless its portraits failed; the same durable action key resumes each paid
 * Blend stage. A finished stage starts the next one in the same call, and each finished milestone pushes once.
 */
export async function advancePaidCharacter(
    userId: string,
    purchaseId: string,
    input: CustomCharacterAdvanceRequest,
) {
    for (let stageNumber = 0; stageNumber < 2; stageNumber++) {
        const stage = await prepareCustomCharacterStage(userId, purchaseId, input);
        if (stage.kind === "portraits") {
            // One rejected portrait must not stop the others; the reconciler retries the rest.
            let failure: ApiError | null = null;
            let progressed = false;
            for (const key of stage.starts) {
                try {
                    await startAiRun(userId, { workflow: "avatar", parameters: { description: stage.description } },
                        key, undefined, purchaseId);
                    progressed = true;
                } catch (error) {
                    if (!(error instanceof ApiError)) throw error;
                    failure ??= error;
                }
            }
            for (const requestId of stage.pending) {
                try {
                    await readAiRun(userId, requestId);
                    progressed = true;
                } catch (error) {
                    if (!(error instanceof ApiError)) throw error;
                    failure ??= error;
                }
            }
            if (failure && !progressed) throw failure;
            break;
        }
        if (stage.kind === "existing") {
            const result = await readAiRun(userId, stage.requestId);
            if (result.workflow === "avatar" && result.status === "completed") continue;
            break;
        }
        const parameters = stage.kind === "avatar"
            ? { workflow: "avatar" as const, parameters: { description: stage.description } }
            : { workflow: "fitness" as const, parameters: {
                avatar_request_id: stage.avatarRequestId,
                identity_details: stage.description,
            } };
        const result = await startAiRun(userId, parameters, stage.key, undefined, purchaseId);
        if (result.workflow === "avatar" && result.status === "completed") continue;
        break;
    }
    let character = await readPaidCharacter(userId, purchaseId);

    const milestone = character.phase === "choosing"
        ? "portraits" as const
        : character.phase === "complete" ? "poses" as const : null;
    // Claim even without APNs, so an owed push cannot keep the purchase in every reconcile batch.
    if (milestone && await claimCustomCharacterPush(userId, purchaseId, milestone)) {
        await sendUserAlert(userId, (french) => milestone === "portraits"
            ? french
                ? { title: "Ton personnage est prêt", body: "Choisis ton portrait préféré parmi les trois." }
                : { title: "Your character is ready", body: "Pick your favourite of the three portraits." }
            : french
                ? { title: "Ton personnage est prêt", body: "Ses cinq poses fitness sont prêtes. Fais-en ton compagnon." }
                : { title: "Your character is ready", body: "All five fitness poses are done. Make it your companion." }, {
            route: `/characters/${purchaseId}`,
            collapseId: `${purchaseId}:${milestone}`,
            imageUrl: character.portrait_url ?? undefined,
        });
    }
    // Suggestions come last, so they never delay or stop the portrait, the poses or the push.
    if (await advanceCompanionLinesBestEffort(userId, purchaseId))
        character = await readPaidCharacter(userId, purchaseId);
    return character;
}

/**
 * Reads a running suggestion batch, so the app sees it finish while it polls, or starts the first batch once a
 * portrait is chosen. With an attempt ID it starts one "Four more" batch instead; the same ID returns the same batch.
 * Returns whether the character's suggestions changed: a batch started or settled.
 */
export async function advanceCompanionLines(
    userId: string,
    purchaseId: string,
    attemptId: string | null,
    deps = { prepare: prepareCompanionLines, start: startAiRun, read: readAiRun },
) {
    const step = await deps.prepare(userId, purchaseId, attemptId);
    if (step.kind === "pending")
        return !["pending", "running"].includes((await deps.read(userId, step.requestId)).status);
    if (step.kind === "none") return false;
    await deps.start(userId, {
        workflow: "companion_lines",
        parameters: {
            avatar_request_id: step.avatarRequestId,
            description: step.description,
            language: step.locale === "fr" ? "fr" : "en",
            avoid: step.avoid,
        },
    }, step.key, undefined, purchaseId);
    return true;
}

/**
 * The suggestion step of the character pass and the reconciler. It never breaks the poses or a reconcile batch: a
 * rejected start or read waits for the next pass. Deferred start codes are expected; any other rejection is logged
 * with its code and purchase only, never the text.
 */
export async function advanceCompanionLinesBestEffort(
    userId: string,
    purchaseId: string,
    advance: typeof advanceCompanionLines = advanceCompanionLines,
) {
    try {
        return await advance(userId, purchaseId, null);
    } catch (error) {
        if (!(error instanceof ApiError)) throw error;
        if (!deferredCharacterStartCodes.includes(error.code))
            console.error(
                "fitfight_companion_lines_failed",
                JSON.stringify({ error_code: error.code, purchase_id: purchaseId }),
            );
        return false;
    }
}

export async function readPaidCharacter(userId: string, purchaseId: string) {
    const store = await readCustomCharacterStore(userId);
    const character = store.characters.find((item) => item.id === purchaseId);
    if (!character) throw new ApiError(404, "not_found", "Character purchase not found");
    return character;
}

/** Saves the owner's pick, then starts the five poses at once when Blend has room; otherwise the reconciler does. */
export async function choosePaidCharacterPortrait(userId: string, purchaseId: string, candidateId: string) {
    await chooseCustomCharacterPortrait(userId, purchaseId, candidateId);
    try {
        return await advancePaidCharacter(userId, purchaseId, {});
    } catch (error) {
        if (!(error instanceof ApiError) || !deferredCharacterStartCodes.includes(error.code)) throw error;
        return readPaidCharacter(userId, purchaseId);
    }
}
