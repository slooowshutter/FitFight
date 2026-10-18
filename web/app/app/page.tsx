"use client";

import { PlusIcon, SwordsIcon } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
    Card,
    CardAction,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
} from "@/components/ui/card";
import {
    Empty,
    EmptyContent,
    EmptyDescription,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
    FightResultBadge,
    FightTimeText,
} from "@/components/web-app/fight-status";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { useMe } from "@/components/web-app/web-app-shell";
import { useFitFightApi } from "@/hooks/use-fitfight-api";
import { webFights } from "@/lib/domain/fights/web-fight-view";
import { fightSnapshotSchema } from "@/lib/types/fights/fight-snapshot";
import type { WebFight } from "@/lib/types/fights/web-fight";

export default function FightsPage() {
    const me = useMe();
    const [filter, setFilter] = useState<"current" | "invited" | "past">(
        "current",
    );
    const snapshot = useFitFightApi("fights/snapshot", fightSnapshotSchema, {
        time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    });
    const fights = snapshot.data ? webFights(snapshot.data, me.user_id) : [];
    const current = fights.filter(
        (fight) => fight.status === "live" || fight.status === "pending",
    );
    const invited = fights.filter((fight) => fight.status === "invited");
    const past = fights.filter((fight) => fight.status === "finished");
    const leading = current.filter(
        (fight) => fight.standings[0]?.you && fight.standings[0].steps > 0,
    );
    const shown = (
        filter === "current" ? current : filter === "invited" ? invited : past
    ).toSorted((left, right) =>
        filter === "past"
            ? right.fight.ends_at.localeCompare(left.fight.ends_at)
            : left.fight.ends_at.localeCompare(right.fight.ends_at),
    );

    return (
        <>
            <div className="flex items-center justify-between gap-4">
                <h1 className="text-3xl font-extrabold tracking-tight">
                    Fights
                </h1>
                <Button asChild>
                    <Link href="/app/new">
                        <PlusIcon data-icon="inline-start" />
                        New fight
                    </Link>
                </Button>
            </div>

            {snapshot.error ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not load your Fights</AlertTitle>
                    <AlertDescription>
                        {snapshot.error.message}
                    </AlertDescription>
                </Alert>
            ) : null}

            <div className="grid gap-4 sm:grid-cols-3">
                {[
                    {
                        label: "Live fights",
                        value: snapshot.data ? String(current.length) : null,
                    },
                    {
                        label: "You lead",
                        value: snapshot.data
                            ? `${leading.length} of ${current.length}`
                            : null,
                    },
                    {
                        label: "Invitations",
                        value: snapshot.data ? String(invited.length) : null,
                    },
                ].map((stat) => (
                    <Card key={stat.label}>
                        <CardHeader>
                            <CardDescription>{stat.label}</CardDescription>
                            <CardTitle className="text-3xl font-extrabold tabular-nums">
                                {stat.value ?? (
                                    <Skeleton className="h-9 w-16" />
                                )}
                            </CardTitle>
                        </CardHeader>
                    </Card>
                ))}
            </div>

            <Tabs
                value={filter}
                onValueChange={(value) =>
                    setFilter(
                        value === "invited" || value === "past"
                            ? value
                            : "current",
                    )
                }
            >
                <TabsList>
                    <TabsTrigger value="current">Current</TabsTrigger>
                    <TabsTrigger value="invited">
                        Invited{invited.length ? ` (${invited.length})` : ""}
                    </TabsTrigger>
                    <TabsTrigger value="past">Past</TabsTrigger>
                </TabsList>
            </Tabs>

            {!snapshot.data && !snapshot.error ? (
                <div className="grid gap-4 lg:grid-cols-2">
                    <Skeleton className="h-56" />
                    <Skeleton className="h-56" />
                </div>
            ) : shown.length === 0 && snapshot.data ? (
                <Empty className="border">
                    <EmptyHeader>
                        <EmptyMedia variant="icon">
                            <SwordsIcon />
                        </EmptyMedia>
                        <EmptyTitle>
                            {filter === "current"
                                ? "No current fights"
                                : filter === "invited"
                                  ? "No invitations"
                                  : "No past fights"}
                        </EmptyTitle>
                        <EmptyDescription>
                            Start one and invite friends by username.
                        </EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent>
                        <Button asChild>
                            <Link href="/app/new">New fight</Link>
                        </Button>
                    </EmptyContent>
                </Empty>
            ) : (
                <div className="grid gap-4 lg:grid-cols-2">
                    {shown.map((fight) => (
                        <FightCard key={fight.fight.id} fight={fight} />
                    ))}
                </div>
            )}
        </>
    );
}

function FightCard({ fight }: { fight: WebFight }) {
    const best = Math.max(
        1,
        ...fight.standings.map((standing) => standing.steps),
    );

    return (
        <Link
            href={`/app/fights/${fight.fight.id}`}
            className="rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
            <Card className="h-full transition-colors hover:bg-accent/40">
                <CardHeader>
                    <CardTitle className="text-lg font-extrabold">
                        {fight.fight.name}
                    </CardTitle>
                    <CardDescription>
                        <FightTimeText fight={fight} />
                    </CardDescription>
                    <CardAction>
                        <FightResultBadge fight={fight} />
                    </CardAction>
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                    {fight.standings.slice(0, 5).map((standing, index) => (
                        <div
                            key={standing.profile.user_id}
                            className="flex items-center gap-3"
                        >
                            <span className="w-4 text-sm font-bold text-muted-foreground tabular-nums">
                                {standing.playing ? index + 1 : ""}
                            </span>
                            <PersonAvatar person={standing.profile} size="sm" />
                            <div className="flex min-w-0 flex-1 flex-col gap-1">
                                <div className="flex items-baseline justify-between gap-2">
                                    <span className="truncate text-sm font-bold">
                                        {standing.you
                                            ? "You"
                                            : standing.profile.display_name}
                                    </span>
                                    <span className="text-sm font-extrabold tabular-nums">
                                        {standing.playing
                                            ? standing.steps.toLocaleString()
                                            : "Invited"}
                                    </span>
                                </div>
                                <div className="h-1.5 overflow-hidden rounded-full bg-track">
                                    <div
                                        className={
                                            standing.you
                                                ? "h-full rounded-full bg-primary"
                                                : "h-full rounded-full bg-muted-foreground/50"
                                        }
                                        style={{
                                            width: `${(standing.steps / best) * 100}%`,
                                        }}
                                    />
                                </div>
                            </div>
                        </div>
                    ))}
                    {fight.standings.length > 5 ? (
                        <span className="text-sm text-muted-foreground">
                            +{fight.standings.length - 5} more
                        </span>
                    ) : null}
                </CardContent>
                {fight.fight.action_text ? (
                    <CardFooter className="mt-auto text-sm text-muted-foreground">
                        Loser: {fight.fight.action_text}
                    </CardFooter>
                ) : null}
            </Card>
        </Link>
    );
}
