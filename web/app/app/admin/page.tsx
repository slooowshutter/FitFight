"use client";

import { cn } from "cn";
import { useState } from "react";
import {
    Bar,
    BarChart,
    CartesianGrid,
    Line,
    LineChart,
    XAxis,
    YAxis,
} from "recharts";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
    Card,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
} from "@/components/ui/card";
import {
    type ChartConfig,
    ChartContainer,
    ChartLegend,
    ChartLegendContent,
    ChartTooltip,
    ChartTooltipContent,
} from "@/components/ui/chart";
import {
    Select,
    SelectContent,
    SelectGroup,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { FitFightApiError, useFitFightApi } from "@/hooks/use-fitfight-api";
import { browserProjectURL } from "@/lib/supabase/browser-client";
import {
    adminDashboardBucketSchema,
    adminDashboardEnvironmentSchema,
    adminDashboardSchema,
    adminDashboardSectionSchema,
    type AdminDashboardCard,
    type AdminDashboardChart,
    type AdminDashboardUnit,
} from "@/lib/types/admin/admin-dashboard";

const periods = [
    { days: "7", label: "7 days" },
    { days: "30", label: "30 days" },
    { days: "90", label: "90 days" },
    { days: "365", label: "1 year" },
    // The server starts the charts at the first signup.
    { days: "3650", label: "All" },
];

// NOTE: A production server only adds production data; staging and `next dev` read both, like the iPhone app.
const productionServer = browserProjectURL.includes("pvqntpteehdvhqyctwum");

/** The iPhone app's admin dashboard: every section's cards and charts, for Production or Staging. */
export default function AdminPage() {
    const [environment, setEnvironment] = useState<"production" | "staging">(
        "production",
    );
    const [section, setSection] = useState("overview");
    const [days, setDays] = useState("30");
    const [bucket, setBucket] = useState("auto");
    const query = `?section=${section}&days=${days}&environment=${environment}${bucket === "auto" ? "" : `&bucket=${bucket}`}`;
    // `next dev` has no production connection, so it reads through the preview server (app/api/v1/dev/admin-dashboard).
    const dashboard = useFitFightApi(
        `${process.env.NODE_ENV === "development" ? "dev/admin-dashboard" : "admin/dashboard"}${query}`,
        adminDashboardSchema,
    );
    const data = dashboard.data;

    return (
        <>
            <div className="flex flex-wrap items-center justify-between gap-4">
                <div className="flex flex-col gap-1">
                    <h1 className="text-3xl font-extrabold tracking-tight">
                        Admin
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        {data
                            ? `Updated ${new Date(data.generated_at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })}`
                            : "Loading"}
                    </p>
                </div>
                {productionServer ? null : (
                    <ToggleGroup
                        type="single"
                        variant="outline"
                        aria-label="Database"
                        value={environment}
                        onValueChange={(value) => {
                            if (value)
                                setEnvironment(
                                    adminDashboardEnvironmentSchema.parse(
                                        value,
                                    ),
                                );
                        }}
                    >
                        <ToggleGroupItem value="production">
                            Production
                        </ToggleGroupItem>
                        <ToggleGroupItem value="staging">
                            Staging
                        </ToggleGroupItem>
                    </ToggleGroup>
                )}
            </div>

            <Tabs
                value={section}
                onValueChange={(value) =>
                    setSection(adminDashboardSectionSchema.parse(value))
                }
            >
                <TabsList className="h-auto flex-wrap">
                    {(
                        data?.sections ?? [
                            { id: "overview", title: "Overview" },
                        ]
                    ).map((item) => (
                        <TabsTrigger key={item.id} value={item.id}>
                            {item.title}
                        </TabsTrigger>
                    ))}
                </TabsList>
            </Tabs>

            <div className="flex flex-wrap items-center gap-3">
                <ToggleGroup
                    type="single"
                    variant="outline"
                    aria-label="Period"
                    value={days}
                    onValueChange={(value) => {
                        if (value) setDays(value);
                    }}
                >
                    {periods.map((period) => (
                        <ToggleGroupItem key={period.days} value={period.days}>
                            {period.label}
                        </ToggleGroupItem>
                    ))}
                </ToggleGroup>
                <Select
                    value={bucket}
                    onValueChange={(value) =>
                        setBucket(
                            value === "auto"
                                ? "auto"
                                : adminDashboardBucketSchema.parse(value),
                        )
                    }
                >
                    <SelectTrigger aria-label="Chart steps" className="w-32">
                        <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                        <SelectGroup>
                            <SelectItem value="auto">Auto</SelectItem>
                            <SelectItem value="day">By day</SelectItem>
                            <SelectItem value="week">By week</SelectItem>
                            <SelectItem value="month">By month</SelectItem>
                        </SelectGroup>
                    </SelectContent>
                </Select>
            </div>

            {dashboard.error ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not load the dashboard</AlertTitle>
                    <AlertDescription>
                        {dashboard.error instanceof FitFightApiError &&
                        dashboard.error.status === 403
                            ? `This account isn't the FitFight admin on ${environment === "production" ? "Production" : "Staging"}.`
                            : dashboard.error.message}
                    </AlertDescription>
                </Alert>
            ) : null}

            {!data && !dashboard.error ? (
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    {[0, 1, 2, 3].map((index) => (
                        <Skeleton key={index} className="h-32" />
                    ))}
                </div>
            ) : null}

            {data ? (
                <>
                    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                        {data.cards.map((card) => (
                            <StatCard key={card.id} card={card} />
                        ))}
                    </div>
                    <div className="grid gap-4 lg:grid-cols-2">
                        {data.charts.map((chart) => (
                            <ChartCard key={chart.id} chart={chart} />
                        ))}
                    </div>
                </>
            ) : null}
        </>
    );
}

function StatCard({ card }: { card: AdminDashboardCard }) {
    const change =
        card.value === null || card.previous === null
            ? null
            : card.value - card.previous;
    const changeText =
        change === null || card.previous === null
            ? null
            : card.unit === "percent"
              ? `${change > 0 ? "+" : ""}${formatValue(change, "count")} pts`
              : card.previous === 0
                ? change === 0
                    ? "No change"
                    : `${change > 0 ? "+" : ""}${formatValue(change, card.unit)} from 0`
                : `${change > 0 ? "+" : ""}${formatValue((change / Math.abs(card.previous)) * 100, "count")}% (${change > 0 ? "+" : ""}${formatValue(change, card.unit)})`;
    const tone =
        change === null || change === 0 || card.higher_is_better === null
            ? "text-muted-foreground"
            : change > 0 === card.higher_is_better
              ? "text-moss-text"
              : "text-ember-text";

    return (
        <Card title={card.definition ?? undefined}>
            <CardHeader>
                <CardDescription>{card.title}</CardDescription>
                <CardTitle className="text-3xl font-extrabold tabular-nums">
                    {card.value === null
                        ? "-"
                        : formatValue(card.value, card.unit)}
                </CardTitle>
            </CardHeader>
            {changeText || card.note ? (
                <CardFooter className="flex-col items-start gap-1 text-xs">
                    {changeText ? (
                        <span className={cn("font-bold tabular-nums", tone)}>
                            {changeText}
                        </span>
                    ) : null}
                    {card.note ? (
                        <span className="text-muted-foreground">
                            {card.note}
                        </span>
                    ) : null}
                </CardFooter>
            ) : null}
        </Card>
    );
}

function ChartCard({ chart }: { chart: AdminDashboardChart }) {
    const label = (x: string) =>
        chart.x_kind === "date"
            ? new Date(`${x.slice(0, 10)}T00:00:00Z`).toLocaleDateString(
                  undefined,
                  { day: "numeric", month: "short", timeZone: "UTC" },
              )
            : x;
    // Series names hold spaces, so the chart keys them by position and labels them by name.
    const config: ChartConfig = Object.fromEntries(
        chart.series.map((series, index) => [
            `s${index}`,
            {
                label: series.name,
                color: series.previous
                    ? "var(--chart-4)"
                    : `var(--chart-${[1, 3, 2, 5][index % 4]})`,
            },
        ]),
    );
    const rows = [
        ...new Set(
            chart.series.flatMap((series) =>
                series.points.map((point) => point.x),
            ),
        ),
    ].map((x) => ({
        x,
        ...Object.fromEntries(
            chart.series.map((series, index) => [
                `s${index}`,
                series.points.find((point) => point.x === x)?.y ?? null,
            ]),
        ),
    }));
    const columns = [...new Set(chart.cells.map((cell) => cell.x))];
    const peak = Math.max(1, ...chart.cells.map((cell) => cell.value));

    return (
        <Card>
            <CardHeader>
                <CardTitle className="font-extrabold">{chart.title}</CardTitle>
                {chart.definition ? (
                    <CardDescription
                        className="line-clamp-2"
                        title={chart.definition}
                    >
                        {chart.definition}
                    </CardDescription>
                ) : null}
            </CardHeader>
            <CardContent>
                {chart.kind === "heatmap" ? (
                    <div className="overflow-x-auto">
                        <div
                            className="grid gap-0.5 text-[10px] text-muted-foreground"
                            style={{
                                gridTemplateColumns: `auto repeat(${columns.length}, minmax(14px, 1fr))`,
                            }}
                        >
                            {[
                                ...new Set(chart.cells.map((cell) => cell.y)),
                            ].map((y) => (
                                <div key={y} className="contents">
                                    <span className="pr-2">{y}</span>
                                    {columns.map((x) => {
                                        const value =
                                            chart.cells.find(
                                                (cell) =>
                                                    cell.x === x &&
                                                    cell.y === y,
                                            )?.value ?? 0;
                                        return (
                                            <div
                                                key={x}
                                                title={`${y} ${x}: ${formatValue(value, chart.unit)}`}
                                                className="aspect-square rounded-sm bg-primary"
                                                style={{
                                                    opacity:
                                                        0.08 +
                                                        (value / peak) * 0.92,
                                                }}
                                            />
                                        );
                                    })}
                                </div>
                            ))}
                        </div>
                    </div>
                ) : rows.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                        No data yet.
                    </p>
                ) : (
                    <ChartContainer
                        config={config}
                        className="aspect-auto h-64 w-full"
                    >
                        {chart.kind === "line" ? (
                            <LineChart data={rows} accessibilityLayer>
                                <CartesianGrid vertical={false} />
                                <XAxis
                                    dataKey="x"
                                    tickFormatter={label}
                                    tickLine={false}
                                    axisLine={false}
                                    minTickGap={24}
                                />
                                <YAxis
                                    tickFormatter={(value: number) =>
                                        formatValue(value, chart.unit)
                                    }
                                    tickLine={false}
                                    axisLine={false}
                                    width={48}
                                />
                                <ChartTooltip
                                    content={
                                        <ChartTooltipContent
                                            labelFormatter={(value) =>
                                                label(String(value))
                                            }
                                        />
                                    }
                                />
                                {chart.series.length > 1 ? (
                                    <ChartLegend
                                        content={<ChartLegendContent />}
                                    />
                                ) : null}
                                {chart.series.map((series, index) => (
                                    <Line
                                        key={series.name}
                                        dataKey={`s${index}`}
                                        stroke={`var(--color-s${index})`}
                                        strokeWidth={2}
                                        strokeDasharray={
                                            series.previous ? "4 4" : undefined
                                        }
                                        dot={false}
                                        connectNulls
                                        isAnimationActive={false}
                                    />
                                ))}
                            </LineChart>
                        ) : (
                            <BarChart data={rows} accessibilityLayer>
                                <CartesianGrid vertical={false} />
                                <XAxis
                                    dataKey="x"
                                    tickFormatter={label}
                                    tickLine={false}
                                    axisLine={false}
                                    minTickGap={12}
                                />
                                <YAxis
                                    tickFormatter={(value: number) =>
                                        formatValue(value, chart.unit)
                                    }
                                    tickLine={false}
                                    axisLine={false}
                                    width={48}
                                />
                                <ChartTooltip
                                    content={
                                        <ChartTooltipContent
                                            labelFormatter={(value) =>
                                                label(String(value))
                                            }
                                        />
                                    }
                                />
                                {chart.series.length > 1 ? (
                                    <ChartLegend
                                        content={<ChartLegendContent />}
                                    />
                                ) : null}
                                {chart.series.map((series, index) => (
                                    <Bar
                                        key={series.name}
                                        dataKey={`s${index}`}
                                        stackId="stack"
                                        fill={`var(--color-s${index})`}
                                        isAnimationActive={false}
                                    />
                                ))}
                            </BarChart>
                        )}
                    </ChartContainer>
                )}
            </CardContent>
            {chart.note ? (
                <CardFooter className="text-xs text-muted-foreground">
                    {chart.note}
                </CardFooter>
            ) : null}
        </Card>
    );
}

/** "1.5K", "42%", "3 h": the iPhone dashboard's compact numbers. */
function formatValue(value: number, unit: AdminDashboardUnit) {
    const suffix = {
        percent: "%",
        days: " d",
        hours: " h",
        minutes: " min",
        seconds: " s",
        count: "",
        steps: "",
    }[unit];
    return (
        new Intl.NumberFormat("en", {
            notation: unit === "percent" ? "standard" : "compact",
            maximumFractionDigits: 1,
        }).format(value) + suffix
    );
}
