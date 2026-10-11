import { startAiRun, readAiRun } from "@/lib/domain/ai/workflow-requests";
import { sendApnsAlert } from "@/lib/apns/apns-client";
import { readApnsEnvironment } from "@/lib/apns/apns-config";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    chooseCustomCharacterPortrait,
    claimCustomCharacterPush,
    prepareCustomCharacterStage,
    readCustomCharacterStore,
} from "@/lib/supabase/queries/custom-characters-supabase-query";
import {
    decryptInstallationToken,
    readActiveDeviceInstallations,
    revokeDeviceInstallation,
} from "@/lib/supabase/queries/device-installations-supabase-query";
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
    const store = await readCustomCharacterStore(userId);
    const character = store.characters.find((item) => item.id === purchaseId);
    if (!character) throw new ApiError(404, "not_found", "Character purchase not found");

    const milestone = character.phase === "choosing"
        ? "portraits" as const
        : character.phase === "complete" ? "poses" as const : null;
    // Claim even without APNs, so an owed push cannot keep the purchase in every reconcile batch.
    const apns = milestone && await claimCustomCharacterPush(userId, purchaseId, milestone) ? readApnsEnvironment() : null;
    if (milestone && apns) {
        const database = createDatabaseClient();
        const installations = await readActiveDeviceInstallations(userId, database);
        const french = installations[0]?.locale === "fr";
        const alert = milestone === "portraits"
            ? french
                ? { title: "Ton personnage est prêt", body: "Choisis ton portrait préféré parmi les trois." }
                : { title: "Your character is ready", body: "Pick your favourite of the three portraits." }
            : french
                ? { title: "Ton personnage est prêt", body: "Ses cinq poses fitness sont prêtes. Fais-en ton compagnon." }
                : { title: "Your character is ready", body: "All five fitness poses are done. Make it your companion." };
        // Best effort, like the other alerts: the first installation that accepts the push is enough.
        for (const installation of installations) {
            let deviceToken: string;
            try {
                deviceToken = decryptInstallationToken(installation);
            } catch {
                await revokeDeviceInstallation(installation.id, "decrypt_failed", database);
                continue;
            }
            const sent = await sendApnsAlert({
                deviceToken,
                environment: installation.apns_environment,
                topic: apns.topic,
                ...alert,
                route: `/characters/${purchaseId}`,
                collapseId: `${purchaseId}:${milestone}`,
                imageUrl: character.portrait_url ?? undefined,
            });
            if (sent.unregistered) {
                await revokeDeviceInstallation(installation.id, sent.reason ?? "unregistered", database);
                continue;
            }
            if (sent.httpStatus === 200 || sent.retryLater || sent.invalidProviderToken) break;
        }
    }
    return character;
}

/** Saves the owner's pick, then starts the five poses at once when Blend has room; otherwise the reconciler does. */
export async function choosePaidCharacterPortrait(userId: string, purchaseId: string, candidateId: string) {
    await chooseCustomCharacterPortrait(userId, purchaseId, candidateId);
    try {
        return await advancePaidCharacter(userId, purchaseId, {});
    } catch (error) {
        if (!(error instanceof ApiError) || !deferredCharacterStartCodes.includes(error.code)) throw error;
        const store = await readCustomCharacterStore(userId);
        const character = store.characters.find((item) => item.id === purchaseId);
        if (!character) throw new ApiError(404, "not_found", "Character purchase not found");
        return character;
    }
}
