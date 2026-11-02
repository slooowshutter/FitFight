import { image, json, text } from "@/lib/ai/steps";
import * as P from "@/lib/ai/prompts";
import type {
    AvatarInput,
    CompanionLinesInput,
    FitnessInput,
    GroupPhotoInput,
    PromptCheckInput,
    RaceStartInput,
    TrailInput,
} from "@/lib/types/ai/step";

// Every FitFight AI workflow. One function per workflow; the helpers own model calls and durable uploads.
// Steps that need each other's answer wait with await; steps that don't run at the same time with Promise.all.
// Sign-in, payment, logging, retries and saving happen around these functions, so a new workflow is only this.
// The prompts are in prompts.ts. Start a workflow with startAiWorkflow (runner.ts), never directly.

const FAST = "z-ai/glm-5.3-flash";
const VISION = "google/gemini-2.5-flash";
const SMART = "anthropic/claude-opus-5.5";
const QUICK = "anthropic/claude-haiku-5.5";
const JUDGE = "anthropic/claude-fable-5.1";
const DRAW = "openai/gpt-image-2.5-sunburst";
// Blend drew characters square: it sent each node's size and ignored its "2K, 2:3" fields.
const SQUARE = "1024x1024";
const WIDE = "1536x1024";
// Blend's "focus" creativity; the other text steps keep the model's own temperature, as Blend sent none.
const FOCUS = 0.1;

/** A custom animal portrait from what the player typed. */
export async function avatar({ request_id, description }: AvatarInput) {
    "use workflow";
    const clean = await text({
        requestId: request_id,
        name: "Clean the description", model: FAST, system: P.AVATAR_CLEAN_SYSTEM, prompt: P.AVATAR_CLEAN_PROMPT,
        vars: { user_request: description }, temperature: FOCUS,
    });
    const image_url = await image({
        requestId: request_id,
        name: "Draw the avatar", model: DRAW, prompt: P.AVATAR_IMAGE_PROMPT, vars: { description: clean },
        images: [P.AVATAR_STYLE_REFERENCE], size: SQUARE,
    });
    return { image_url };
}

/** The same character at five fitness levels, from its portrait. */
export async function fitness({ request_id, portraits, identity_details }: FitnessInput) {
    "use workflow";
    // Lists the portrait's accessories, so none of the five drawings forgets one.
    const signature_items = await text({
        requestId: request_id,
        name: "List the signature items", model: VISION, system: P.SIGNATURE_ITEMS_SYSTEM,
        prompt: P.SIGNATURE_ITEMS_PROMPT, vars: { identity_details }, images: portraits, temperature: FOCUS,
    });
    const draw = (name: string, prompt: string) =>
        image({ requestId: request_id, name, model: DRAW, prompt, vars: { signature_items }, images: [...portraits, P.FITNESS_STAGE_SHEET], size: SQUARE });
    const [resting, soft, average, fit, strong] = await Promise.all([
        draw("Draw resting", P.FITNESS_RESTING_PROMPT),
        draw("Draw soft", P.FITNESS_SOFT_PROMPT),
        draw("Draw average", P.FITNESS_AVERAGE_PROMPT),
        draw("Draw fit", P.FITNESS_FIT_PROMPT),
        draw("Draw strong", P.FITNESS_STRONG_PROMPT),
    ]);
    return { resting, soft, average, fit, strong };
}

/** Several saved characters together in one transparent scene. */
export async function groupPhoto({ request_id, portraits, scene, cast_roster }: GroupPhotoInput) {
    "use workflow";
    const cleanScene = await text({
        requestId: request_id,
        name: "Keep the scene in scope", model: FAST, system: P.GROUP_SCENE_SYSTEM, prompt: P.GROUP_SCENE_PROMPT,
        vars: { scene_request: scene }, temperature: FOCUS,
    });
    // ponytail: Blend also ran a count check here that nothing read; the fight images below use theirs.
    const image_url = await image({
        requestId: request_id,
        name: "Draw the group", model: DRAW, prompt: P.GROUP_PHOTO_PROMPT, vars: { scene: cleanScene, cast_roster },
        images: portraits, size: WIDE,
    });
    return { image_url };
}

/** Four name and line ideas for a custom companion. Returns { options }. */
export async function companionLines({ request_id, portraits, description, language, avoid }: CompanionLinesInput) {
    "use workflow";
    return json({
        requestId: request_id,
        name: "Write names and lines", model: SMART, system: P.COMPANION_LINES_SYSTEM, prompt: P.COMPANION_LINES_PROMPT,
        vars: { description, language, avoid }, images: portraits, reasoning: "low",
    });
}

/** Checks what a player typed before they buy: an optional note and three richer rewrites. */
export async function promptCheck({ request_id, description, language }: PromptCheckInput) {
    "use workflow";
    return json({
        requestId: request_id,
        name: "Check the description", model: QUICK, system: P.PROMPT_CHECK_SYSTEM, prompt: P.PROMPT_CHECK_PROMPT,
        vars: { description, language },
    });
}

/** A fight's group image for up to 16 runners, then a count of who was drawn. */
export async function trail({ portraits, cast_roster, scene }: TrailInput) {
    "use workflow";
    const cleanScene = await text({
        requestId: null,
        name: "Keep the scene in scope", model: FAST, system: P.TRAIL_SCENE_SYSTEM, prompt: P.TRAIL_SCENE_PROMPT,
        vars: { scene_request: scene }, temperature: FOCUS,
    });
    const image_url = await image({
        requestId: null,
        name: "Draw the runners", model: DRAW, prompt: P.TRAIL_IMAGE_PROMPT, vars: { scene: cleanScene, cast_roster },
        images: portraits, size: WIDE,
    });
    const check = await text({
        requestId: null,
        name: "Count the runners", model: JUDGE, prompt: P.TRAIL_COUNT_PROMPT, vars: { cast_roster },
        images: [image_url], reasoning: "medium",
    });
    return { image_url, check };
}

/** A fight's group image for 17 runners or more: 12 featured runners and a crowd, then a count. */
export async function raceStart({ portraits, cast_roster, crowd_size, crowd_companions }: RaceStartInput) {
    "use workflow";
    const image_url = await image({
        requestId: null,
        name: "Draw the race start", model: DRAW, prompt: P.RACE_START_IMAGE_PROMPT,
        vars: { cast_roster, crowd_size, crowd_companions }, images: portraits, size: WIDE,
    });
    const check = await text({
        requestId: null,
        name: "Count the featured runners", model: JUDGE, prompt: P.RACE_START_COUNT_PROMPT, vars: { cast_roster },
        images: [image_url], reasoning: "medium",
    });
    return { image_url, check };
}
