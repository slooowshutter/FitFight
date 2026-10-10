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
export const adminDashboardBucketValues = ["day", "week", "month"] as const;

export const adminDashboardSectionSchema = z.enum(adminDashboardSectionValues);
export const adminDashboardUnitSchema = z.enum(adminDashboardUnitValues);
export const adminDashboardEnvironmentSchema = z.enum(adminDashboardEnvironmentValues);
export const adminDashboardBucketSchema = z.enum(adminDashboardBucketValues);

export const adminDashboardQuerySchema = z.object({
    section: adminDashboardSectionSchema,
    days: z.coerce.number().int().min(1).max(3650),
    environment: adminDashboardEnvironmentSchema.optional(),
    /** Omitted: days up to 62 days, weeks up to a year, then months. */
    bucket: adminDashboardBucketSchema.optional(),
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
    /** What the chart measures, for its detail page. */
    definition: z.string().nullable(),
    /** A sentence that reads one current number off the chart. */
    example: z.string().nullable(),
    series: z.array(adminDashboardSeriesSchema),
    cells: z.array(
        z.object({ x: z.string(), y: z.string(), value: z.number().finite() }),
    ),
});

export const adminDashboardSchema = z.object({
    section: adminDashboardSectionSchema,
    days: z.number().int(),
    environment: adminDashboardEnvironmentSchema,
    /** The bucket of the charts over time. */
    bucket: adminDashboardBucketSchema,
    generated_at: z.string(),
    /** Every section in chip order: the app draws its chips from this list. */
    sections: z.array(z.object({ id: adminDashboardSectionSchema, title: z.string() })),
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
});

/** The first chart day, already at the start of its bucket. */
export const adminDashboardRangeRowSchema = z.object({
    start: z.string(),
    bucket: adminDashboardBucketSchema,
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
export type AdminDashboardBucket = z.infer<typeof adminDashboardBucketSchema>;
export type AdminDashboardIdentity = z.infer<typeof adminDashboardIdentityRowSchema>;

/** The verified admin's account on this server's project and its Apple or Google accounts. */
export type AdminDashboardAdmin = { userId: string; identities: AdminDashboardIdentity[] };
export type AdminDashboardQuery = z.infer<typeof adminDashboardQuerySchema>;
export type AdminDashboardCard = z.infer<typeof adminDashboardCardSchema>;
export type AdminDashboardChart = z.infer<typeof adminDashboardChartSchema>;
export type AdminDashboard = z.infer<typeof adminDashboardSchema>;

export type AdminDashboardQueryFragment = PendingQuery<Row[]>;

/**
 * Cards use fixed spans from `now` (rolling) or `today` (complete Paris days). Charts over time
 * cover Paris days from `start`, a bucket start, through today.
 */
export type AdminDashboardWindow = {
    now: Date;
    today: string;
    start: string;
    bucket: AdminDashboardBucket;
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
    definition: string;
    /** Null when the chart has no number to read yet. */
    example?: (read: AdminDashboardExampleReader) => string | null;
    query: AdminDashboardQueryFragment;
};

/** What a chart's example sentence reads from the points the chart draws. */
export type AdminDashboardExampleReader = {
    /** The date-chart bucket a sentence reads: the newest complete one ("on Thu 9 Oct",
     * "in the week of 29 Sep", "in September 2026"), else the newest ("today so far"). */
    when: string;
    /** A series' value at that bucket; the first series when no name is given. */
    at: (series?: string) => number | undefined;
    /** A series' newest value, for running totals and states. */
    latest: (series?: string) => number | undefined;
    /** A series' oldest point. */
    first: (series?: string) => { x: string; y: number } | undefined;
    series: AdminDashboardChart["series"];
    /** Label charts: the first series' rows in order, one row's value, their total, and the largest row. */
    rows: { x: string; y: number }[];
    row: (label: string) => number | undefined;
    total: number;
    top: { x: string; y: number; share: string | undefined } | undefined;
    /** Heatmaps: the busiest cell. */
    peak: { x: string; y: string; value: number } | undefined;
    /** "8,234", "42%", "1.2 seconds"; the chart's unit by default. */
    format: (value: number, unit?: AdminDashboardUnit) => string;
    /** "1 person", "6 people". */
    count: (value: number, one: string, many: string) => string;
    /** "42%" of a whole, or undefined when the whole is 0. */
    share: (part: number, whole: number) => string | undefined;
    /** "Thu 9 Oct" for a date x. */
    day: (x: string) => string;
    /** A date chart's bucket by its x: "Thu 9 Oct", "the week of 5 Oct" or "October 2026". */
    period: (x: string) => string;
};
