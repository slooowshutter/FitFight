import type { PendingQuery, Row } from "postgres";
import { z } from "zod";

export const adminDashboardSectionValues = [
    "overview",
    "retention",
    "users",
    "engagement",
    "steps",
    "fights",
    "social",
    "app",
] as const;
export const adminDashboardUnitValues = [
    "count",
    "steps",
    "percent",
    "days",
    "hours",
    "minutes",
    "seconds",
] as const;
export const adminDashboardChartKindValues = ["line", "bar", "heatmap"] as const;
export const adminDashboardXKindValues = ["date", "label"] as const;
export const adminDashboardEnvironmentValues = ["production", "staging"] as const;

export const adminDashboardSectionSchema = z.enum(adminDashboardSectionValues);
export const adminDashboardUnitSchema = z.enum(adminDashboardUnitValues);
export const adminDashboardEnvironmentSchema = z.enum(adminDashboardEnvironmentValues);

export const adminDashboardQuerySchema = z.object({
    section: adminDashboardSectionSchema,
    days: z.coerce.number().int().min(1).max(3650),
    environment: adminDashboardEnvironmentSchema.optional(),
});

export const adminDashboardCardSchema = z.object({
    id: z.string(),
    title: z.string(),
    value: z.number().finite().nullable(),
    previous: z.number().finite().nullable(),
    unit: adminDashboardUnitSchema,
    higher_is_better: z.boolean().nullable(),
    note: z.string().nullable(),
});

export const adminDashboardSeriesSchema = z.object({
    name: z.string(),
    previous: z.boolean(),
    points: z.array(z.object({ x: z.string(), y: z.number().finite() })),
});

export const adminDashboardChartSchema = z.object({
    id: z.string(),
    title: z.string(),
    kind: z.enum(adminDashboardChartKindValues),
    unit: adminDashboardUnitSchema,
    x_kind: z.enum(adminDashboardXKindValues),
    note: z.string().nullable(),
    series: z.array(adminDashboardSeriesSchema),
    cells: z.array(
        z.object({ x: z.string(), y: z.string(), value: z.number().finite() }),
    ),
});

export const adminDashboardSchema = z.object({
    section: adminDashboardSectionSchema,
    days: z.number().int(),
    environment: adminDashboardEnvironmentSchema,
    generated_at: z.string(),
    cards: z.array(adminDashboardCardSchema),
    charts: z.array(adminDashboardChartSchema),
});

export const adminDashboardCardRowSchema = z.object({
    value: z.coerce.number().finite().nullable(),
    previous: z.coerce.number().finite().nullable(),
});

export const adminDashboardChartRowSchema = z.object({
    x: z.string(),
    y: z.coerce.number().finite(),
    series: z.string().nullable().optional(),
    previous: z.boolean().nullable().optional(),
});

export const adminDashboardCellRowSchema = z.object({
    x: z.string(),
    y: z.string(),
    value: z.coerce.number().finite(),
});

/** Supabase Auth returns each linked Apple or Google identity with the provider's subject. */
export const adminDashboardIdentitySchema = z.object({
    provider: z.string(),
    identity_data: z.object({ sub: z.string().min(1) }).passthrough(),
});

export const adminDashboardLinkedAccountSchema = z.object({ user_id: z.string().uuid() });

/** `subject` is `auth.identities.provider_id`: one Apple or Google account has the same subject in both FitFight projects. */
export const adminDashboardIdentityRowSchema = z.object({
    provider: z.string(),
    subject: z.string().min(1),
});

export const adminDashboardProductionAdminRowSchema = z.object({ handle: z.string() });

export type AdminDashboardSection = z.infer<typeof adminDashboardSectionSchema>;
export type AdminDashboardUnit = z.infer<typeof adminDashboardUnitSchema>;
export type AdminDashboardEnvironment = z.infer<typeof adminDashboardEnvironmentSchema>;
export type AdminDashboardIdentity = z.infer<typeof adminDashboardIdentityRowSchema>;

/** The verified admin's account on this server's project and its Apple or Google accounts. */
export type AdminDashboardAdmin = { userId: string; identities: AdminDashboardIdentity[] };
export type AdminDashboardQuery = z.infer<typeof adminDashboardQuerySchema>;
export type AdminDashboardCard = z.infer<typeof adminDashboardCardSchema>;
export type AdminDashboardChart = z.infer<typeof adminDashboardChartSchema>;
export type AdminDashboard = z.infer<typeof adminDashboardSchema>;

export type AdminDashboardQueryFragment = PendingQuery<Row[]>;

/** Rolling windows for event cards, Paris calendar days for charts and Steps. */
export type AdminDashboardWindow = {
    now: Date;
    start: Date;
    previousStart: Date;
    today: string;
    days: number;
    chartDays: number;
    bucket: "day" | "week" | "month";
};

export type AdminDashboardCardDefinition = {
    id: string;
    title: string;
    unit: AdminDashboardUnit;
    better: boolean | null;
    note?: string;
    query: AdminDashboardQueryFragment;
};

export type AdminDashboardChartDefinition = {
    id: string;
    title: string;
    kind: AdminDashboardChart["kind"];
    unit: AdminDashboardUnit;
    x: AdminDashboardChart["x_kind"];
    note?: string;
    query: AdminDashboardQueryFragment;
};
