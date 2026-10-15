"use client";

import { ChevronLeftIcon, MessageCircleIcon, SwordsIcon } from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { Bar, BarChart, CartesianGrid, XAxis } from "recharts";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from "@/components/ui/card";
import {
    type ChartConfig,
    ChartContainer,
    ChartTooltip,
    ChartTooltipContent,
} from "@/components/ui/chart";
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog";
import {
    Empty,
    EmptyContent,
    EmptyDescription,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table";
import {
    FightResultBadge,
    FightTimeText,
} from "@/components/web-app/fight-status";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { useMe } from "@/components/web-app/web-app-shell";
import { fitfightApi, useFitFightApi } from "@/hooks/use-fitfight-api";
import { webFights } from "@/lib/domain/fights/web-fight-view";
import { timeAgo } from "@/lib/format/time-ago";
import { fightPostListResponseSchema } from "@/lib/types/feed/fight-post";
import { fightSnapshotSchema } from "@/lib/types/fights/fight-snapshot";
import { fightSummaryResponseSchema } from "@/lib/types/fights/fight-summary";

export default function FightDetailPage() {
    const { fightID } = useParams<{ fightID: string }>();
    const me = useMe();
    const router = useRouter();
    const [confirmDelete, setConfirmDelete] = useState(false);
    const [busy, setBusy] = useState(false);
    const [actionError, setActionError] = useState<string | null>(null);
    const snapshot = useFitFightApi("fights/snapshot", fightSnapshotSchema, {
        time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    });
    const fight = snapshot.data
        ? webFights(snapshot.data, me.user_id).find(
              (candidate) => candidate.fight.id === fightID,
          )
        : undefined;
    const posts = useFitFightApi(
        fight && fight.status !== "invited"
            ? `fights/${fightID}/posts?limit=10`
            : null,
        fightPostListResponseSchema,
    );

    async function run(action: "accept" | "decline" | "leave" | "cancel") {
        setBusy(true);
        setActionError(null);
        try {
            await fitfightApi(
                action === "leave"
                    ? "fights/leave"
                    : `fights/${fightID}/${action}`,
                fightSummaryResponseSchema,
                {
                    body:
                        action === "accept"
                            ? { start: "now" }
                            : action === "leave"
                              ? { fightId: fightID }
                              : {},
                },
            );
            setConfirmDelete(false);
            if (action === "decline" || action === "leave") {
                router.push("/app");
            } else {
                snapshot.reload();
            }
        } catch (error) {
            setActionError(
                error instanceof Error ? error.message : "Something went wrong",
            );
        } finally {
            setBusy(false);
        }
    }

    const back = (
        <Button variant="ghost" size="sm" className="w-fit" asChild>
            <Link href="/app">
                <ChevronLeftIcon data-icon="inline-start" />
                Fights
            </Link>
        </Button>
    );

    const loadError = snapshot.error ? (
        <Alert variant="destructive">
            <AlertTitle>Could not load this fight</AlertTitle>
            <AlertDescription>{snapshot.error.message}</AlertDescription>
        </Alert>
    ) : null;

    if (!snapshot.data) {
        return (
            <>
                {back}
                {loadError ?? (
                    <>
                        <Skeleton className="h-12 w-72" />
                        <Skeleton className="h-64" />
                        <div className="grid gap-4 lg:grid-cols-2">
                            <Skeleton className="h-72" />
                            <Skeleton className="h-72" />
                        </div>
                    </>
                )}
            </>
        );
    }

    if (!fight) {
        return (
            <Empty className="border">
                <EmptyHeader>
                    <EmptyMedia variant="icon">
                        <SwordsIcon />
                    </EmptyMedia>
                    <EmptyTitle>Fight not found</EmptyTitle>
                    <EmptyDescription>
                        It may have ended, or you are no longer in it.
                    </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                    <Button asChild>
                        <Link href="/app">Back to Fights</Link>
                    </Button>
                </EmptyContent>
            </Empty>
        );
    }

    const timeZone =
        fight.fight.time_zone ??
        Intl.DateTimeFormat().resolvedOptions().timeZone;
    const you = fight.standings.find((standing) => standing.you);
    const leader = fight.standings[0];
    const racers = fight.standings.filter((standing) => standing.playing);
    const stepDays = snapshot.data.step_days;
    const owner = snapshot.data.profiles.find(
        (profile) => profile.user_id === fight.fight.owner_id,
    );
    const isOwner = fight.fight.owner_id === me.user_id;
    const upcoming = new Date(fight.fight.starts_at) > new Date();
    const inFightZone = (iso: string) =>
        new Date(iso).toLocaleString(undefined, {
            dateStyle: "medium",
            timeStyle: "short",
            timeZone,
        });

    // Days follow the app's rule: calendar days in the fight's time zone, from its start to its last instant.
    const dayKey = (date: Date) =>
        new Intl.DateTimeFormat("en-CA", {
            timeZone,
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
        }).format(date);
    const lastDay = [
        dayKey(new Date(Date.parse(fight.fight.ends_at) - 1)),
        dayKey(new Date()),
    ].sort()[0];
    const chartRows: Record<string, string | number | null>[] = [];
    for (
        let day = dayKey(new Date(fight.fight.starts_at));
        day <= lastDay && chartRows.length < 41;
        day = new Date(Date.parse(day) + 86_400_000).toISOString().slice(0, 10)
    ) {
        chartRows.push({
            label: new Date(`${day}T00:00:00Z`).toLocaleDateString(undefined, {
                weekday: "short",
                day: "numeric",
                month: "short",
                timeZone: "UTC",
            }),
            ...Object.fromEntries(
                racers.map((standing) => [
                    standing.profile.user_id,
                    stepDays.find(
                        (row) =>
                            row.user_id === standing.profile.user_id &&
                            row.day === day,
                    )?.steps ?? null,
                ]),
            ),
        });
    }
    const chartConfig: ChartConfig = Object.fromEntries(
        racers.map((standing) => [
            standing.profile.user_id,
            {
                label: standing.you ? "You" : standing.profile.display_name,
                color: standing.you ? "var(--chart-1)" : "var(--chart-4)",
            },
        ]),
    );

    return (
        <>
            {back}
            {loadError}

            <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex min-w-0 flex-col gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                        <h1 className="text-3xl font-extrabold tracking-tight">
                            {fight.fight.name}
                        </h1>
                        {fight.status === "invited" ? null : (
                            <Badge variant="outline">
                                {fight.status === "pending"
                                    ? "Pending"
                                    : fight.status === "finished"
                                      ? fight.fight.state === "cancelled"
                                          ? "Cancelled"
                                          : "Ended"
                                      : upcoming
                                        ? "Upcoming"
                                        : "Live"}
                            </Badge>
                        )}
                        <FightResultBadge fight={fight} />
                    </div>
                    <p className="text-muted-foreground">
                        <FightTimeText fight={fight} />
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    {fight.status === "invited" ? (
                        <>
                            <Button
                                disabled={busy}
                                onClick={() => run("accept")}
                            >
                                {busy ? (
                                    <Spinner data-icon="inline-start" />
                                ) : null}
                                Accept challenge
                            </Button>
                            <Button
                                variant="outline"
                                disabled={busy}
                                onClick={() => run("decline")}
                            >
                                Decline
                            </Button>
                        </>
                    ) : null}
                    {!isOwner &&
                    (fight.status === "live" || fight.status === "pending") &&
                    (you?.member.state === "accepted" ||
                        you?.member.state === "deferred") ? (
                        <Button
                            variant="outline"
                            disabled={busy}
                            onClick={() => run("leave")}
                        >
                            Leave fight
                        </Button>
                    ) : null}
                    {isOwner &&
                    fight.fight.state !== "final" &&
                    fight.fight.state !== "cancelled" ? (
                        <Button
                            variant="destructive"
                            disabled={busy}
                            onClick={() => {
                                setActionError(null);
                                setConfirmDelete(true);
                            }}
                        >
                            Delete fight
                        </Button>
                    ) : null}
                </div>
            </div>

            {actionError && !confirmDelete ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not update this fight</AlertTitle>
                    <AlertDescription>{actionError}</AlertDescription>
                </Alert>
            ) : null}

            <Card>
                <CardHeader>
                    <CardTitle className="text-lg font-extrabold">
                        Standings
                    </CardTitle>
                    <CardDescription>Most steps wins.</CardDescription>
                </CardHeader>
                <CardContent>
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead className="w-12">#</TableHead>
                                <TableHead>Name</TableHead>
                                <TableHead className="text-right">
                                    Steps
                                </TableHead>
                                <TableHead className="text-right">
                                    Gap
                                </TableHead>
                                <TableHead className="text-right">
                                    Last synced
                                </TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {fight.standings.map((standing, index) => (
                                <TableRow
                                    key={standing.profile.user_id}
                                    className={
                                        standing.you
                                            ? "bg-moss-wash hover:bg-moss-wash"
                                            : undefined
                                    }
                                >
                                    <TableCell className="font-bold text-muted-foreground tabular-nums">
                                        {standing.playing
                                            ? fight.status === "finished"
                                                ? (standing.member.rank ??
                                                  index + 1)
                                                : index + 1
                                            : "-"}
                                    </TableCell>
                                    <TableCell>
                                        <Link
                                            href={`/app/people/${standing.profile.user_id}`}
                                            className="flex w-fit items-center gap-3 rounded-md outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
                                        >
                                            <PersonAvatar
                                                person={standing.profile}
                                                size="sm"
                                            />
                                            <span className="flex min-w-0 flex-col">
                                                <span
                                                    className={
                                                        standing.you
                                                            ? "truncate font-extrabold text-moss-text"
                                                            : "truncate font-bold hover:underline"
                                                    }
                                                >
                                                    {standing.you
                                                        ? "You"
                                                        : standing.profile
                                                              .display_name}
                                                </span>
                                                <span className="truncate text-xs text-muted-foreground">
                                                    @{standing.profile.handle}
                                                </span>
                                            </span>
                                        </Link>
                                    </TableCell>
                                    <TableCell className="text-right font-extrabold tabular-nums">
                                        {standing.playing ? (
                                            standing.steps.toLocaleString()
                                        ) : (
                                            <Badge variant="secondary">
                                                {standing.member.state ===
                                                "deferred"
                                                    ? "Next round"
                                                    : "Invited"}
                                            </Badge>
                                        )}
                                    </TableCell>
                                    <TableCell className="text-right text-muted-foreground tabular-nums">
                                        {standing.playing &&
                                        leader &&
                                        leader.steps > standing.steps
                                            ? `${(leader.steps - standing.steps).toLocaleString()} behind`
                                            : "-"}
                                    </TableCell>
                                    <TableCell className="text-right text-muted-foreground">
                                        {!standing.playing
                                            ? "-"
                                            : fight.status !== "live" &&
                                                standing.member
                                                    .final_steps_complete
                                              ? "Final steps synced"
                                              : standing.member.last_synced_at
                                                ? timeAgo(
                                                      standing.member
                                                          .last_synced_at,
                                                  )
                                                : "Not synced yet"}
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>

            <div className="grid gap-4 lg:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle className="text-lg font-extrabold">
                            Every day so far
                        </CardTitle>
                        <CardDescription>
                            Daily steps. Only synced steps are shown.
                        </CardDescription>
                    </CardHeader>
                    <CardContent>
                        {fight.status === "invited" ||
                        chartRows.length === 0 ||
                        racers.length === 0 ? (
                            <p className="text-sm text-muted-foreground">
                                {fight.status === "invited"
                                    ? "Accept the challenge to see daily steps."
                                    : "No steps yet."}
                            </p>
                        ) : (
                            <ChartContainer
                                config={chartConfig}
                                className="aspect-auto h-64 w-full"
                            >
                                <BarChart data={chartRows} accessibilityLayer>
                                    <CartesianGrid vertical={false} />
                                    <XAxis
                                        dataKey="label"
                                        tickLine={false}
                                        axisLine={false}
                                        tickMargin={8}
                                    />
                                    <ChartTooltip
                                        content={<ChartTooltipContent />}
                                    />
                                    {racers.map((standing) => (
                                        <Bar
                                            key={standing.profile.user_id}
                                            dataKey={standing.profile.user_id}
                                            fill={`var(--color-${standing.profile.user_id})`}
                                            radius={4}
                                            isAnimationActive={false}
                                        />
                                    ))}
                                </BarChart>
                            </ChartContainer>
                        )}
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle className="text-lg font-extrabold">
                            Details
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-3 text-sm">
                            {[
                                {
                                    label: "Start",
                                    value: inFightZone(fight.fight.starts_at),
                                },
                                {
                                    label: "End",
                                    value: inFightZone(fight.fight.ends_at),
                                },
                                { label: "Time zone", value: timeZone },
                                {
                                    label: "Created by",
                                    value: isOwner
                                        ? "You"
                                        : owner?.display_name,
                                },
                                {
                                    label: "Participants",
                                    value: `${racers.length} in this fight`,
                                },
                                {
                                    label: "Loser action",
                                    value: fight.fight.action_text,
                                },
                                {
                                    label: "Fight code",
                                    value: fight.series?.join_code,
                                },
                                {
                                    label: "Visibility",
                                    value: fight.series
                                        ? fight.series.visibility === "joinable"
                                            ? "Public"
                                            : "Private"
                                        : null,
                                },
                                {
                                    label: "Repeats",
                                    value: fight.series
                                        ? fight.series.recurring
                                            ? "Yes, each round has its own result"
                                            : "No"
                                        : null,
                                },
                            ].map((row) =>
                                row.value ? (
                                    <div key={row.label} className="contents">
                                        <dt className="text-muted-foreground">
                                            {row.label}
                                        </dt>
                                        <dd className="font-bold">
                                            {row.value}
                                        </dd>
                                    </div>
                                ) : null,
                            )}
                        </dl>
                    </CardContent>
                </Card>
            </div>

            {fight.status === "invited" ? null : (
                <Card>
                    <CardHeader>
                        <CardTitle className="text-lg font-extrabold">
                            Posts
                        </CardTitle>
                        <CardDescription>
                            What people shared in this fight.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-4">
                        {posts.error ? (
                            <Alert variant="destructive">
                                <AlertTitle>Could not load posts</AlertTitle>
                                <AlertDescription>
                                    {posts.error.message}
                                </AlertDescription>
                            </Alert>
                        ) : !posts.data ? (
                            <>
                                <Skeleton className="h-20" />
                                <Skeleton className="h-20" />
                            </>
                        ) : posts.data.posts.length === 0 ? (
                            <Empty>
                                <EmptyHeader>
                                    <EmptyMedia variant="icon">
                                        <MessageCircleIcon />
                                    </EmptyMedia>
                                    <EmptyTitle>No posts yet</EmptyTitle>
                                    <EmptyDescription>
                                        Posts shared in this fight show up here.
                                    </EmptyDescription>
                                </EmptyHeader>
                            </Empty>
                        ) : (
                            posts.data.posts.map((post) => (
                                <div
                                    key={post.id}
                                    className="flex gap-3 border-b pb-4 last:border-b-0 last:pb-0"
                                >
                                    <Link
                                        href={`/app/people/${post.author.user_id}`}
                                        className="shrink-0"
                                    >
                                        <PersonAvatar person={post.author} />
                                    </Link>
                                    <div className="flex min-w-0 flex-1 flex-col gap-2">
                                        <div className="flex items-baseline gap-2">
                                            <Link
                                                href={`/app/people/${post.author.user_id}`}
                                                className="truncate font-bold hover:underline"
                                            >
                                                {post.mine
                                                    ? "You"
                                                    : post.author.display_name}
                                            </Link>
                                            <span className="shrink-0 text-xs text-muted-foreground">
                                                {timeAgo(post.created_at)}
                                            </span>
                                        </div>
                                        {post.body ? (
                                            <p className="text-sm whitespace-pre-wrap">
                                                {post.body}
                                            </p>
                                        ) : null}
                                        {post.media.map((media) =>
                                            media.kind === "photo" &&
                                            media.url ? (
                                                <img
                                                    key={media.id}
                                                    src={media.url}
                                                    alt=""
                                                    className="max-h-80 w-fit max-w-full rounded-lg border object-cover"
                                                />
                                            ) : null,
                                        )}
                                        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                                            {post.reactions.map((reaction) => (
                                                <Badge
                                                    key={reaction.emoji}
                                                    variant={
                                                        reaction.mine
                                                            ? "default"
                                                            : "secondary"
                                                    }
                                                >
                                                    {reaction.emoji}{" "}
                                                    {reaction.count}
                                                </Badge>
                                            ))}
                                            <span className="tabular-nums">
                                                {post.comment_count}{" "}
                                                {post.comment_count === 1
                                                    ? "comment"
                                                    : "comments"}
                                            </span>
                                        </div>
                                    </div>
                                </div>
                            ))
                        )}
                    </CardContent>
                </Card>
            )}

            <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Delete fight?</DialogTitle>
                        <DialogDescription>
                            This ends the fight for everyone in it. If it
                            repeats, the next rounds stop too. This can't be
                            undone.
                        </DialogDescription>
                    </DialogHeader>
                    {actionError ? (
                        <Alert variant="destructive">
                            <AlertDescription>{actionError}</AlertDescription>
                        </Alert>
                    ) : null}
                    <DialogFooter>
                        <DialogClose asChild>
                            <Button variant="outline">Cancel</Button>
                        </DialogClose>
                        <Button
                            variant="destructive"
                            disabled={busy}
                            onClick={() => run("cancel")}
                        >
                            {busy ? <Spinner data-icon="inline-start" /> : null}
                            Delete
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}
