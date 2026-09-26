import { startAiRun, readAiRun } from "@/lib/domain/ai/workflow-requests";
import { ApiError } from "@/lib/http";
import {
    prepareCustomCharacterStage,
    readCustomCharacterStore,
} from "@/lib/supabase/queries/custom-characters-supabase-query";
import type { CustomCharacterAdvanceRequest } from "@/lib/types/ai/custom-character";

/** A purchase keeps one description unless its portrait failed; the same durable action key resumes each paid Blend stage. */
export async function advancePaidCharacter(
    userId: string,
    purchaseId: string,
    input: CustomCharacterAdvanceRequest,
) {
    for (let stageNumber = 0; stageNumber < 2; stageNumber++) {
        const stage = await prepareCustomCharacterStage(userId, purchaseId, input);
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
    return character;
}
