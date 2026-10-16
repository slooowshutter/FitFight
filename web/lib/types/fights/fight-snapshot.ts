import { z } from "zod";
import { companionIdSchema } from "@/lib/types/companions/companion";
import { mediaObjectSchema } from "@/lib/types/media/media";
import {
    fightMemberStateValues,
    fightStateValues,
} from "./membership-decision";
import { fightVisibilityValues } from "./fight-visibility";
import { fightStepCheckpointSchema } from "./fight-step-checkpoint";

const timestampSchema = z.string().datetime({ offset: true });

export const fightSnapshotRequestSchema = z
    .object({
        time_zone: z
            .string()
            .min(1)
            .max(100)
            .refine((timeZone) => {
                try {
                    new Intl.DateTimeFormat("en-US", { timeZone }).format();
                    return true;
                } catch {
                    return false;
                }
            }, "invalid time zone"),
        /** Only the caller's current hosted rounds, such as a founder's challengers. */
        hosted: z.boolean().optional(),
        /** Only the caller's current friend rounds where both friends still race. */
        friends: z.boolean().optional(),
    })
    .strict();

export const fightSnapshotSchema = z.object({
    fights: z.array(
        z.object({
            id: z.string().uuid(),
            owner_id: z.string().uuid(),
            name: z.string(),
            state: z.enum(fightStateValues),
            starts_at: timestampSchema,
            ends_at: timestampSchema,
            time_zone: z.string().optional(),
            grace_ends_at: timestampSchema,
            action_text: z.string().nullable(),
            series_id: z.string().uuid().nullable(),
            /** Always sent by current servers; absent from older responses. */
            friends: z.boolean().optional(),
        }),
    ),
    members: z.array(
        z.object({
            fight_id: z.string().uuid(),
            user_id: z.string().uuid(),
            state: z.enum(fightMemberStateValues),
            current_value: z.number().finite().nullable(),
            rank: z.number().int().nullable(),
            final_value: z.number().finite().nullable(),
            last_synced_at: timestampSchema.nullable(),
            final_steps_complete: z.boolean(),
            step_checkpoints: z
                .array(fightStepCheckpointSchema)
                .nullable()
                .optional(),
        }),
    ),
    profiles: z.array(
        z.object({
            user_id: z.string().uuid(),
            handle: z.string(),
            display_name: z.string(),
            avatar: mediaObjectSchema.nullable(),
            companion_id: companionIdSchema.nullable().default(null),
            companion_image_url: z.string().url().optional(),
        }),
    ),
    series: z.array(
        z.object({
            id: z.string().uuid(),
            join_code: z.string().nullable(),
            visibility: z.enum(fightVisibilityValues),
            recurring: z.boolean(),
            suggested: z.boolean(),
        }),
    ),
    step_days: z.array(
        z.object({
            user_id: z.string().uuid(),
            day: z.string().date(),
            steps: z.number().int().nonnegative(),
        }),
    ),
    /** One card for everything the caller hosts: its current rounds and how many the host leads. */
    hosted: z
        .object({
            name: z.string(),
            rounds: z.number().int().positive(),
            leading: z.number().int().nonnegative(),
        })
        .nullable(),
    /**
     * The caller's Friends card, always sent by current servers and absent from older responses.
     * leading counts rounds the caller is strictly ahead in; requests counts incoming friend requests.
     */
    friends: z
        .object({
            rounds: z.number().int().nonnegative(),
            leading: z.number().int().nonnegative(),
            requests: z.number().int().nonnegative(),
        })
        .optional(),
});

/** The caller's friendships as GET /friends shows them: blocked and deleted people left out. */
export const snapshotFriendshipsRowSchema = z.object({
    requests: z.number().int().nonnegative(),
    friend_ids: z.array(z.string().uuid()),
});

export const fightMaintenanceCandidateSchema = z.object({
    id: z.string().uuid(),
    state: z.enum(fightStateValues),
    starts_at: timestampSchema,
    ends_at: timestampSchema,
});

export const userFightMaintenanceSchema = z.object({
    candidates: z.array(fightMaintenanceCandidateSchema),
    recurring: z.array(z.string().uuid()),
});

export type FightSnapshotRequest = z.infer<typeof fightSnapshotRequestSchema>;
export type FightSnapshot = z.infer<typeof fightSnapshotSchema>;
export type SnapshotFriendshipsRow = z.infer<typeof snapshotFriendshipsRowSchema>;
export type FightMaintenanceCandidate = z.infer<
    typeof fightMaintenanceCandidateSchema
>;
export type UserFightMaintenance = z.infer<typeof userFightMaintenanceSchema>;
