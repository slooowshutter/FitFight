import { z } from "zod";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";
import { fightVisibilitySchema } from "./joinable-fight";
import { timeZoneSchema } from "@/lib/types/time/time-zone";

const dateTime = z
    .string()
    .refine(
        (value) => Number.isFinite(Date.parse(value)),
        "must be a date-time",
    );

export const updateFightRequestSchema = z
    .object({
        name: z.string().trim().max(120).optional(),
        actionText: z.string().trim().max(120).optional(),
        visibility: fightVisibilitySchema.optional(),
        recurring: z.boolean().optional(),
        startsAt: dateTime.optional(),
        endsAt: dateTime.optional(),
        timeZone: timeZoneSchema.optional(),
        joinCode: z
            .string()
            .transform(normalizeJoinCode)
            .refine(
                isJoinCode,
                "Use 4 to 12 letters or numbers",
            )
            .optional(),
        inviteHandles: z.array(z.string()).optional(),
        removeUserIds: z.array(z.string().uuid()).optional(),
        /** On: close 24 hours after the end with last synced totals. Off: wait for everyone's final Steps. */
        closesAfterGrace: z.boolean().optional(),
    })
    .superRefine((value, ctx) => {
        const hasField =
            value.name !== undefined ||
            value.actionText !== undefined ||
            value.visibility !== undefined ||
            value.recurring !== undefined ||
            value.startsAt !== undefined ||
            value.endsAt !== undefined ||
            value.timeZone !== undefined ||
            value.joinCode !== undefined ||
            value.closesAfterGrace !== undefined ||
            (value.inviteHandles !== undefined &&
                value.inviteHandles.length > 0) ||
            (value.removeUserIds !== undefined &&
                value.removeUserIds.length > 0);
        if (!hasField) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "Nothing to update",
            });
        }
        if (
            value.startsAt &&
            value.endsAt &&
            Date.parse(value.endsAt) <= Date.parse(value.startsAt)
        ) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                message: "endsAt must be after startsAt",
                path: ["endsAt"],
            });
        }
    });

export type UpdateFightRequest = z.infer<typeof updateFightRequestSchema>;
