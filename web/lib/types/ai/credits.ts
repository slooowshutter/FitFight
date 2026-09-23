import { z } from "zod";

export const aiCreditStateValues = [
    "none",
    "reserved",
    "consumed",
    "released",
] as const;
export const aiBalanceEventKindValues = [
    "grant",
    "reserve",
    "consume",
    "release",
    "adjustment",
] as const;

export const aiAllowanceSchema = z.object({
    available: z.number().int().nonnegative(),
    reserved: z.number().int().nonnegative(),
    avatar_price: z.number().int().positive(),
    fitness_price: z.number().int().positive().nullable().optional(),
    group_photo_price: z.number().int().positive().nullable().optional(),
});
export const aiCreditPricesSchema = z.object({
    fitness_price: z.preprocess(
        (value) => (value === "" ? undefined : value),
        z.coerce.number().int().positive().max(100_000).optional(),
    ),
    group_photo_price: z.preprocess(
        (value) => (value === "" ? undefined : value),
        z.coerce.number().int().positive().max(100_000).optional(),
    ),
});
export const aiCreditBalanceSchema = z.object({
    user_id: z.string().uuid().toLowerCase(),
    available: z.number().int().nonnegative(),
    reserved: z.number().int().nonnegative(),
    sequence: z.number().int().nonnegative(),
});
export const aiBalanceEventSchema = z.object({
    id: z.string().uuid(),
    user_id: z.string().uuid().toLowerCase(),
    sequence: z.number().int().positive(),
    created_at: z.coerce.date(),
    kind: z.enum(aiBalanceEventKindValues),
    reason: z.string().regex(/^[a-z][a-z0-9_]{0,79}$/),
    actor: z.string().max(80),
    operation_key: z.string().max(200),
    request_id: z.string().uuid().nullable(),
    action_key: z.string().uuid().nullable(),
    compensates_event_id: z.string().uuid().nullable(),
    quantity: z.number().int().positive(),
    available_before: z.number().int().nonnegative(),
    available_change: z.number().int(),
    available_after: z.number().int().nonnegative(),
    reserved_before: z.number().int().nonnegative(),
    reserved_change: z.number().int(),
    reserved_after: z.number().int().nonnegative(),
});
export const aiCreditAdjustmentSchema = z.discriminatedUnion("kind", [
    z
        .object({
            kind: z.literal("grant"),
            user_id: z.string().uuid().toLowerCase(),
            operation_key: z.string().uuid().toLowerCase(),
            quantity: z.number().int().positive().max(100_000),
            reason: aiBalanceEventSchema.shape.reason,
        })
        .strict(),
    z
        .object({
            kind: z.literal("adjustment"),
            user_id: z.string().uuid().toLowerCase(),
            operation_key: z.string().uuid().toLowerCase(),
            change: z
                .number()
                .int()
                .min(-100_000)
                .max(100_000)
                .refine((value) => value !== 0),
            compensates_event_id: z.string().uuid().toLowerCase(),
            reason: aiBalanceEventSchema.shape.reason,
        })
        .strict(),
]);
export const aiOperatorConfigurationSchema = z.object({
    FITFIGHT_ADMIN_USER_ID: z.preprocess(
        (value) => (value === "" ? undefined : value),
        z.string().uuid().optional(),
    ),
});
export const aiRecoverySchema = z.discriminatedUnion("action", [
    z
        .object({
            action: z.literal("attach_run"),
            operation_key: z.string().uuid().toLowerCase(),
            run_id: z.string().regex(/^[a-zA-Z0-9_-]{1,200}$/),
            evidence: z.string().regex(/^[a-zA-Z0-9_:/.-]{1,200}$/),
        })
        .strict(),
    z
        .object({
            action: z.literal("confirm_not_accepted"),
            operation_key: z.string().uuid().toLowerCase(),
            evidence: z.string().regex(/^[a-zA-Z0-9_:/.-]{1,200}$/),
        })
        .strict(),
]);

export type AiCreditPrices = z.infer<typeof aiCreditPricesSchema>;
export type AiAllowance = z.infer<typeof aiAllowanceSchema>;
export type AiCreditBalance = z.infer<typeof aiCreditBalanceSchema>;
export type AiBalanceEvent = z.infer<typeof aiBalanceEventSchema>;
export type AiCreditAdjustment = z.infer<typeof aiCreditAdjustmentSchema>;
export type AiOperatorConfiguration = z.infer<
    typeof aiOperatorConfigurationSchema
>;
export type AiRecovery = z.infer<typeof aiRecoverySchema>;
export type AiBalanceChange = Pick<
    AiBalanceEvent,
    | "user_id"
    | "kind"
    | "reason"
    | "actor"
    | "operation_key"
    | "request_id"
    | "action_key"
    | "compensates_event_id"
    | "quantity"
    | "available_change"
    | "reserved_change"
>;
