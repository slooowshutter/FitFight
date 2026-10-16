import { z } from "zod";

/**
 * Fight group images, approved by Marc on 16 Oct 2026. Not secrets, so they live here, not in the environment.
 * Set enabled to false to stop queuing and starting images; running ones still finish.
 */
export const fightImageConfiguration = {
    enabled: true,
    trail: { workflowId: "6a08d9c0-8520-46da-a2e4-129a23f9154a" },
    raceStart: { workflowId: "963f78bf-b8af-46f7-a89f-650d41224e0e" },
    /** A change waits this long so joins and companion changes close together make one image. */
    waitMinutes: 60,
    /** Images started per fight in any rolling 24 hours. */
    perFightPerDay: 2,
    /** Blend runs per image before it is marked failed; each retry is a new run with the same inputs. */
    maxAttempts: 3,
    /** Images started across the whole app in any rolling 24 hours, a cost ceiling. */
    globalPerDay: 200,
    /** Images running at once across the app. */
    maxRunning: 6,
    /** From this many runners the race start replaces the straight trail. */
    raceStartFrom: 17,
    /** Runners drawn in full in a race start; everyone else is in the crowd. */
    featured: 12,
    /** A run that stays unfinished this long counts as a failed attempt. */
    runTimeoutMinutes: 30,
} as const;

export const fightImageLayoutValues = ["trail", "race_start"] as const;
export const fightImageLayoutSchema = z.enum(fightImageLayoutValues);

export const companionKindValues = ["stock", "special", "custom"] as const;
export const companionKindSchema = z.enum(companionKindValues);

/** One accepted runner as drawn: its companion's caption name, description and portrait. */
export const fightImageRunnerSchema = z.object({
    userId: z.string().uuid(),
    isOwner: z.boolean(),
    acceptedAt: z.string().nullable(),
    kind: companionKindSchema,
    /** Same value for runners who share a companion; a custom companion is keyed by its image. */
    companionKey: z.string(),
    rosterName: z.string().min(1),
    description: z.string(),
    artUrl: z.string().url().nullable(),
});

/** What the Blend count check returns. Extra fields are ignored. */
export const fightImageCheckSchema = z.object({
    total: z.coerce.number().int(),
    counts: z.array(z.object({ name: z.string(), count: z.coerce.number().int() })),
    unknown: z.coerce.number().int().default(0),
    facing_left: z.coerce.number().int().default(0),
    crowd_estimate: z.coerce.number().int().optional(),
    text_in_image: z.boolean().optional(),
});

export const fightImageJobRowSchema = z.object({
    id: z.string().uuid(),
    fight_id: z.string().uuid(),
    status: z.enum(["waiting", "running", "ready", "failed", "cancelled"]),
    attempts: z.number().int(),
    layout: fightImageLayoutSchema.nullable(),
    workflow_id: z.string().nullable(),
    run_id: z.string().nullable(),
    inputs: z.record(z.unknown()).nullable(),
    runners: z.array(fightImageRunnerSchema).nullable(),
    updated_at: z.coerce.date(),
});

export const fightImageCastRowSchema = z.object({
    user_id: z.string().uuid(),
    is_owner: z.boolean(),
    accepted_at: z.coerce.date().nullable(),
    companion_id: z.string().nullable(),
    companion_image_url: z.string().nullable(),
    companion_prompt: z.string().nullable(),
});

export type FightImageLayout = z.infer<typeof fightImageLayoutSchema>;
export type CompanionKind = z.infer<typeof companionKindSchema>;
export type FightImageRunner = z.infer<typeof fightImageRunnerSchema>;
export type FightImageCheck = z.infer<typeof fightImageCheckSchema>;
export type FightImageJobRow = z.infer<typeof fightImageJobRowSchema>;
export type FightImageCastRow = z.infer<typeof fightImageCastRowSchema>;
