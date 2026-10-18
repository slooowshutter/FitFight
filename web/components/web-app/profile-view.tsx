"use client";

import {
    CheckIcon,
    LockIcon,
    LogOutIcon,
    PencilIcon,
    SearchIcon,
    SwordsIcon,
    TrophyIcon,
    UserPlusIcon,
    UsersIcon,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { Bar, BarChart, CartesianGrid, XAxis } from "recharts";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
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
    ChartContainer,
    ChartTooltip,
    ChartTooltipContent,
    type ChartConfig,
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
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuGroup,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
    Empty,
    EmptyDescription,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
    InputGroup,
    InputGroupAddon,
    InputGroupButton,
    InputGroupInput,
} from "@/components/ui/input-group";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { useMe, useReloadMe } from "@/components/web-app/web-app-shell";
import { fitfightApi, useFitFightApi } from "@/hooks/use-fitfight-api";
import { signOut } from "@/lib/supabase/browser-client";
import { cn } from "cn";
import {
    friendsPageSchema,
    friendsQuerySchema,
    friendshipResponseSchema,
    type FriendsPage,
    type FriendsQuery,
    type FriendshipAction,
} from "@/lib/types/friends/friendship";
import { profileSchema } from "@/lib/types/profiles/profile";
import {
    profileHistoryPageSchema,
    type ProfileHistoryPage,
    type ProfileHistoryRow,
} from "@/lib/types/profiles/profile-results";
import {
    profileRivalrySummarySchema,
    profileViewResponseSchema,
    sharedIdentitySchema,
    sharedProfileSchema,
    type profileEntryPointValues,
    type SharedIdentity,
} from "@/lib/types/profiles/shared-profile";

const resultLabels: Record<ProfileHistoryRow["result"], string> = {
    win: "Won",
    loss: "Lost",
    draw: "Draw",
    withdrawn: "Withdrew",
    removed: "Removed",
    incomplete: "Incomplete final sync",
    cancelled: "Cancelled",
    ongoing: "Ongoing",
    solo: "Solo Fight",
    not_entered: "Did not enter",
    unavailable: "Historical result unavailable",
};

const levelNames = {
    couch: "Couch",
    warming_up: "Warming up",
    moving: "Moving",
    active: "Active",
    ripped: "Ripped",
};

const rivalriesSchema = profileRivalrySummarySchema.array();

const stepsChart = {
    steps: { label: "Steps", color: "var(--chart-1)" },
} satisfies ChartConfig;

/** One person's Profile: yours on the Profile tab, anyone else's on their People page, like the app's You and ProfileSheet. */
export function ProfileView({
    userID,
    source,
}: {
    userID: string;
    source?: (typeof profileEntryPointValues)[number];
}) {
    const me = useMe();
    const reloadMe = useReloadMe();
    const own = userID === me.user_id;
    const profile = useFitFightApi(`profiles/${userID}`, sharedProfileSchema);
    const rivals = useFitFightApi(own ? "me/rivalries" : null, rivalriesSchema);
    const history = useFitFightApi(
        `profiles/${userID}/history?shared=${!own}`,
        profileHistoryPageSchema,
    );
    const [olderHistory, setOlderHistory] = useState<ProfileHistoryPage | null>(
        null,
    );
    const {
        busy,
        error: actionError,
        setError: setActionError,
        run,
    } = useTask();
    const [editing, setEditing] = useState(false);
    const [name, setName] = useState("");
    const [eventID] = useState(() => crypto.randomUUID());
    const data = profile.data;
    const stats = data?.step_statistics;
    const historyRows = [
        ...(history.data?.results ?? []),
        ...(olderHistory?.results ?? []),
    ];
    const historyCursor = olderHistory
        ? olderHistory.next_cursor
        : history.data?.next_cursor;
    const recordView =
        !own && source !== undefined && data?.view_measurement_enabled === true;

    useEffect(() => {
        if (!recordView) return;
        // Like the app, measurement never disturbs the Profile, so a failed view is dropped.
        fitfightApi(`profiles/${userID}/views`, profileViewResponseSchema, {
            body: { event_id: eventID, source },
        }).catch(() => undefined);
    }, [recordView, userID, eventID, source]);

    function friendship(action: FriendshipAction) {
        run(async () => {
            await changeFriendship(userID, action);
            profile.reload();
        });
    }

    const statCards: {
        label: string;
        value: string;
        note?: string;
        className?: string;
    }[] = [];
    if (
        !own &&
        data?.rivalry &&
        data.rivalry.wins + data.rivalry.losses + data.rivalry.draws > 0
    ) {
        statCards.push({
            label: "Your rivalry",
            value: `${data.rivalry.wins}-${data.rivalry.losses}-${data.rivalry.draws}`,
            note: "Wins, losses, draws. Decided 1v1 Fights only.",
        });
    }
    if (data?.record) {
        statCards.push(
            {
                label: "Won",
                value: data.record.wins.toLocaleString(),
                className: "text-moss-text",
            },
            {
                label: "Lost",
                value: data.record.losses.toLocaleString(),
                className: "text-ember-text",
            },
            { label: "Drew", value: data.record.draws.toLocaleString() },
            {
                label: "Win rate",
                value:
                    data.record.win_rate === null
                        ? "-"
                        : `${Math.round(data.record.win_rate * 100)}%`,
                note: `${data.record.played.toLocaleString()} fights played`,
            },
        );
    }
    if (stats) {
        statCards.push(
            {
                label: "This week",
                value: Math.round(stats.week.total_steps).toLocaleString(),
                note: `${stats.week.recorded_days} of ${stats.week.elapsed_days} elapsed days recorded`,
            },
            {
                label: "Daily average",
                value:
                    stats.average_steps === null
                        ? "-"
                        : Math.round(stats.average_steps).toLocaleString(),
                note: stats.scope_days
                    ? `Last ${stats.scope_days} days`
                    : "Per recorded day",
            },
            {
                label: "Best day",
                value: stats.best_day
                    ? Math.round(stats.best_day.steps).toLocaleString()
                    : "-",
                note: stats.best_day
                    ? new Date(
                          `${stats.best_day.day}T00:00:00`,
                      ).toLocaleDateString(undefined, {
                          weekday: "short",
                          day: "numeric",
                          month: "short",
                      })
                    : "No completed days recorded yet",
            },
            {
                label: "Recorded days",
                value: stats.recorded_days.toLocaleString(),
                note: `${stats.unknown_days} unknown days`,
            },
        );
    }

    return (
        <>
            <h1 className="text-3xl font-extrabold tracking-tight">Profile</h1>

            {profile.error ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not load this profile</AlertTitle>
                    <AlertDescription>{profile.error.message}</AlertDescription>
                </Alert>
            ) : null}
            {actionError && !editing ? (
                <Alert variant="destructive">
                    <AlertTitle>That did not work</AlertTitle>
                    <AlertDescription>{actionError}</AlertDescription>
                </Alert>
            ) : null}

            {data ? (
                <Card>
                    <CardHeader className="flex flex-wrap items-center gap-4">
                        <PersonAvatar
                            person={identityAvatar(data.identity)}
                            className="size-16"
                        />
                        <div className="flex min-w-0 flex-1 flex-col gap-1">
                            <CardTitle className="truncate text-2xl font-extrabold">
                                {data.identity.display_name}
                            </CardTitle>
                            <CardDescription className="truncate">
                                @{data.identity.handle}
                            </CardDescription>
                        </div>
                        <CardAction className="flex flex-wrap gap-2">
                            {own ? (
                                <>
                                    <Button
                                        variant="outline"
                                        onClick={() => {
                                            setName(data.identity.display_name);
                                            setActionError(null);
                                            setEditing(true);
                                        }}
                                    >
                                        <PencilIcon data-icon="inline-start" />
                                        Edit profile
                                    </Button>
                                    <Button
                                        variant="ghost"
                                        onClick={() => signOut()}
                                    >
                                        <LogOutIcon data-icon="inline-start" />
                                        Sign out
                                    </Button>
                                </>
                            ) : (
                                <>
                                    {data.friendship === "outgoing" ? (
                                        <Button
                                            variant="secondary"
                                            disabled={busy}
                                            onClick={() => friendship("remove")}
                                        >
                                            Requested, cancel
                                        </Button>
                                    ) : data.friendship === "incoming" ? (
                                        <>
                                            <Button
                                                disabled={busy}
                                                onClick={() =>
                                                    friendship("accept")
                                                }
                                            >
                                                Accept
                                            </Button>
                                            <Button
                                                variant="secondary"
                                                disabled={busy}
                                                onClick={() =>
                                                    friendship("decline")
                                                }
                                            >
                                                Decline
                                            </Button>
                                        </>
                                    ) : data.friendship === "friends" ? (
                                        <DropdownMenu>
                                            <DropdownMenuTrigger asChild>
                                                <Button
                                                    variant="secondary"
                                                    disabled={busy}
                                                >
                                                    <CheckIcon data-icon="inline-start" />
                                                    Friends
                                                </Button>
                                            </DropdownMenuTrigger>
                                            <DropdownMenuContent align="end">
                                                <DropdownMenuGroup>
                                                    <DropdownMenuItem
                                                        variant="destructive"
                                                        onSelect={() =>
                                                            friendship("remove")
                                                        }
                                                    >
                                                        Remove friend
                                                    </DropdownMenuItem>
                                                </DropdownMenuGroup>
                                            </DropdownMenuContent>
                                        </DropdownMenu>
                                    ) : (
                                        <Button
                                            disabled={busy}
                                            onClick={() =>
                                                friendship("request")
                                            }
                                        >
                                            <UserPlusIcon data-icon="inline-start" />
                                            Add friend
                                        </Button>
                                    )}
                                    <Button variant="outline" asChild>
                                        <Link
                                            href={`/app/new?handle=${data.identity.handle}`}
                                        >
                                            <SwordsIcon data-icon="inline-start" />
                                            Challenge
                                        </Link>
                                    </Button>
                                </>
                            )}
                        </CardAction>
                    </CardHeader>
                    {!own && data.access === "private" ? (
                        <CardContent>
                            <Alert>
                                <LockIcon />
                                <AlertTitle>Private profile</AlertTitle>
                                <AlertDescription>
                                    Friends and current opponents can see what
                                    this person shares.
                                </AlertDescription>
                            </Alert>
                        </CardContent>
                    ) : !own && !data.competitive ? (
                        <CardContent className="text-sm text-muted-foreground">
                            Keeps the score private.
                        </CardContent>
                    ) : null}
                </Card>
            ) : !profile.error ? (
                <Skeleton className="h-28" />
            ) : null}

            {data ? (
                statCards.length > 0 ? (
                    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                        {statCards.map((stat) => (
                            <Card key={stat.label}>
                                <CardHeader>
                                    <CardDescription>
                                        {stat.label}
                                    </CardDescription>
                                    <CardTitle
                                        className={cn(
                                            "text-3xl font-extrabold tabular-nums",
                                            stat.className,
                                        )}
                                    >
                                        {stat.value}
                                    </CardTitle>
                                    {stat.note ? (
                                        <CardDescription className="text-xs">
                                            {stat.note}
                                        </CardDescription>
                                    ) : null}
                                </CardHeader>
                            </Card>
                        ))}
                    </div>
                ) : null
            ) : !profile.error ? (
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    {[0, 1, 2, 3].map((index) => (
                        <Skeleton key={index} className="h-28" />
                    ))}
                </div>
            ) : null}

            {data?.activity || stats ? (
                <div className="grid gap-4 lg:grid-cols-2">
                    {data?.activity ? (
                        <Card>
                            <CardHeader>
                                <CardTitle className="font-extrabold">
                                    Steps · last {data.activity.days} days
                                </CardTitle>
                                <CardDescription>
                                    Only stored days are shown. Missing days are
                                    unknown, not zero.
                                </CardDescription>
                            </CardHeader>
                            <CardContent>
                                {data.activity.values.length > 0 ? (
                                    <ChartContainer
                                        config={stepsChart}
                                        className="aspect-auto h-60 w-full"
                                    >
                                        <BarChart
                                            accessibilityLayer
                                            data={data.activity.values}
                                        >
                                            <CartesianGrid vertical={false} />
                                            <XAxis
                                                dataKey="day"
                                                tickLine={false}
                                                axisLine={false}
                                                tickMargin={8}
                                                tickFormatter={(day: string) =>
                                                    new Date(
                                                        `${day}T00:00:00`,
                                                    ).toLocaleDateString(
                                                        undefined,
                                                        {
                                                            weekday: "short",
                                                            day: "numeric",
                                                        },
                                                    )
                                                }
                                            />
                                            <ChartTooltip
                                                cursor={false}
                                                content={
                                                    <ChartTooltipContent
                                                        labelFormatter={(day) =>
                                                            new Date(
                                                                `${day}T00:00:00`,
                                                            ).toLocaleDateString(
                                                                undefined,
                                                                {
                                                                    weekday:
                                                                        "long",
                                                                    day: "numeric",
                                                                    month: "long",
                                                                },
                                                            )
                                                        }
                                                    />
                                                }
                                            />
                                            <Bar
                                                dataKey="steps"
                                                fill="var(--color-steps)"
                                                radius={6}
                                                isAnimationActive={false}
                                            />
                                        </BarChart>
                                    </ChartContainer>
                                ) : (
                                    <Empty>
                                        <EmptyHeader>
                                            <EmptyTitle>
                                                No steps yet
                                            </EmptyTitle>
                                            <EmptyDescription>
                                                {own
                                                    ? "Connect Apple Health in the iPhone app to see your Steps here."
                                                    : "No shared days available."}
                                            </EmptyDescription>
                                        </EmptyHeader>
                                    </Empty>
                                )}
                            </CardContent>
                        </Card>
                    ) : null}
                    {stats ? (
                        <Card>
                            <CardHeader>
                                <CardTitle className="font-extrabold">
                                    Days by activity level
                                </CardTitle>
                                <CardDescription>
                                    {stats.scope_days
                                        ? `Last ${stats.scope_days} days.`
                                        : "Your recorded history."}{" "}
                                    Completed days only, through yesterday.
                                </CardDescription>
                            </CardHeader>
                            <CardContent className="flex flex-col gap-4">
                                {stats.levels.map((level) => (
                                    <div
                                        key={level.level}
                                        className="flex flex-col gap-1.5"
                                    >
                                        <div className="flex items-baseline justify-between gap-2 text-sm">
                                            <span className="font-bold">
                                                {levelNames[level.level]}
                                            </span>
                                            <span className="text-muted-foreground tabular-nums">
                                                {level.days}{" "}
                                                {level.days === 1
                                                    ? "day"
                                                    : "days"}
                                                {level.share === null
                                                    ? ""
                                                    : ` · ${Math.round(level.share * 100)}%`}
                                            </span>
                                        </div>
                                        <Progress
                                            value={(level.share ?? 0) * 100}
                                            className="[&_[data-slot=progress-indicator]]:bg-gold"
                                        />
                                        <span className="text-xs text-muted-foreground tabular-nums">
                                            {level.level === "ripped"
                                                ? `${level.minimum_steps.toLocaleString()}+ steps`
                                                : `${level.minimum_steps.toLocaleString()} to ${(level.minimum_steps + 1_999).toLocaleString()} steps`}
                                            {` · Best recorded streak: ${level.longest_streak} ${level.longest_streak === 1 ? "day" : "days"}`}
                                            {level.current_streak
                                                ? ` · Current streak: ${level.current_streak} ${level.current_streak === 1 ? "day" : "days"}`
                                                : ""}
                                        </span>
                                    </div>
                                ))}
                            </CardContent>
                        </Card>
                    ) : null}
                </div>
            ) : null}

            {own && rivals.data && rivals.data.length > 0 ? (
                <Card>
                    <CardHeader>
                        <CardTitle className="font-extrabold">
                            Your rivalries
                        </CardTitle>
                        <CardDescription>
                            Decided 1v1 Fights only.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-3 md:grid-cols-2">
                        {rivals.data.map((rival) => (
                            <PersonRow
                                key={rival.identity.user_id}
                                person={rival.identity}
                                from="friends"
                            >
                                <span className="text-sm font-extrabold tabular-nums">
                                    <span className="text-moss-text">
                                        {rival.rivalry.wins}
                                    </span>
                                    -
                                    <span className="text-ember-text">
                                        {rival.rivalry.losses}
                                    </span>
                                    -
                                    <span className="text-muted-foreground">
                                        {rival.rivalry.draws}
                                    </span>
                                </span>
                            </PersonRow>
                        ))}
                    </CardContent>
                </Card>
            ) : null}
            {own && rivals.error ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not load your rivalries</AlertTitle>
                    <AlertDescription>{rivals.error.message}</AlertDescription>
                </Alert>
            ) : null}

            <Card>
                <CardHeader>
                    <CardTitle className="font-extrabold">
                        {own ? "Fight history" : "Fights together"}
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    {history.error ? (
                        <Alert variant="destructive">
                            <AlertTitle>Could not load the history</AlertTitle>
                            <AlertDescription>
                                {history.error.message}
                            </AlertDescription>
                        </Alert>
                    ) : !history.data ? (
                        <Skeleton className="h-32" />
                    ) : historyRows.length === 0 ? (
                        <Empty>
                            <EmptyHeader>
                                <EmptyMedia variant="icon">
                                    <TrophyIcon />
                                </EmptyMedia>
                                <EmptyTitle>
                                    {own
                                        ? "No results yet"
                                        : "No Fights together yet"}
                                </EmptyTitle>
                            </EmptyHeader>
                        </Empty>
                    ) : (
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Fight</TableHead>
                                    <TableHead>Result</TableHead>
                                    <TableHead>Place</TableHead>
                                    <TableHead className="text-right">
                                        Ends
                                    </TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {historyRows.map((row) => (
                                    <TableRow key={row.id}>
                                        <TableCell className="font-bold">
                                            {row.fight_id ? (
                                                <Link
                                                    href={`/app/fights/${row.fight_id}`}
                                                    className="hover:underline"
                                                >
                                                    {row.name ?? "Fight result"}
                                                </Link>
                                            ) : (
                                                (row.name ?? "Fight result")
                                            )}
                                        </TableCell>
                                        <TableCell>
                                            <Badge
                                                variant={
                                                    row.result === "win"
                                                        ? "default"
                                                        : row.result === "loss"
                                                          ? "destructive"
                                                          : "secondary"
                                                }
                                            >
                                                {resultLabels[row.result]}
                                            </Badge>
                                        </TableCell>
                                        <TableCell className="tabular-nums">
                                            {row.placement
                                                ? `${row.placement} of ${row.field_size}`
                                                : "-"}
                                        </TableCell>
                                        <TableCell className="text-right text-muted-foreground tabular-nums">
                                            {new Date(
                                                row.ends_at,
                                            ).toLocaleDateString(undefined, {
                                                day: "numeric",
                                                month: "short",
                                                year: "numeric",
                                            })}
                                        </TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                        </Table>
                    )}
                </CardContent>
                {historyCursor ? (
                    <CardFooter>
                        <Button
                            variant="ghost"
                            disabled={busy}
                            onClick={() =>
                                run(async () => {
                                    const page = await fitfightApi(
                                        `profiles/${userID}/history?shared=${!own}&cursor=${historyCursor}`,
                                        profileHistoryPageSchema,
                                    );
                                    setOlderHistory({
                                        results: [
                                            ...(olderHistory?.results ?? []),
                                            ...page.results,
                                        ],
                                        next_cursor: page.next_cursor,
                                    });
                                })
                            }
                        >
                            Load more
                        </Button>
                    </CardFooter>
                ) : null}
            </Card>

            {own ? <FriendsCard /> : null}

            <Dialog open={editing} onOpenChange={setEditing}>
                <DialogContent>
                    <form
                        className="flex flex-col gap-4"
                        onSubmit={(event) => {
                            event.preventDefault();
                            run(async () => {
                                await fitfightApi("me", profileSchema, {
                                    method: "PATCH",
                                    body: { display_name: name.trim() },
                                });
                                setEditing(false);
                                profile.reload();
                                reloadMe();
                            });
                        }}
                    >
                        <DialogHeader>
                            <DialogTitle>Edit profile</DialogTitle>
                            <DialogDescription>
                                Your name shows on Fights and the Feed.
                            </DialogDescription>
                        </DialogHeader>
                        <FieldGroup>
                            <Field>
                                <FieldLabel htmlFor="display-name">
                                    Name
                                </FieldLabel>
                                <Input
                                    id="display-name"
                                    placeholder="Display name"
                                    value={name}
                                    onChange={(event) =>
                                        setName(event.target.value)
                                    }
                                />
                            </Field>
                        </FieldGroup>
                        {actionError ? (
                            <Alert variant="destructive">
                                <AlertTitle>Could not save</AlertTitle>
                                <AlertDescription>
                                    {actionError}
                                </AlertDescription>
                            </Alert>
                        ) : null}
                        <DialogFooter>
                            <DialogClose asChild>
                                <Button type="button" variant="outline">
                                    Cancel
                                </Button>
                            </DialogClose>
                            <Button
                                type="submit"
                                disabled={busy || !name.trim()}
                            >
                                Save
                            </Button>
                        </DialogFooter>
                    </form>
                </DialogContent>
            </Dialog>
        </>
    );
}

/** The app's embedded Friends list: friends, requests and sent, plus an exact username search. */
function FriendsCard() {
    const [kind, setKind] = useState<FriendsQuery["kind"]>("accepted");
    const friends = useFitFightApi(`friends?kind=${kind}`, friendsPageSchema);
    const [older, setOlder] = useState<FriendsPage | null>(null);
    const [handle, setHandle] = useState("");
    const [found, setFound] = useState<SharedIdentity | null>(null);
    const { busy, error, run } = useTask();
    const people = [...(friends.data?.people ?? []), ...(older?.people ?? [])];
    const cursor = older ? older.next_cursor : friends.data?.next_cursor;

    function respond(person: SharedIdentity, action: FriendshipAction) {
        run(async () => {
            await changeFriendship(person.user_id, action);
            setOlder(null);
            friends.reload();
        });
    }

    return (
        <Card>
            <CardHeader>
                <CardTitle className="font-extrabold">Friends</CardTitle>
                <CardAction>
                    <Tabs
                        value={kind}
                        onValueChange={(value) => {
                            const next =
                                friendsQuerySchema.shape.kind.safeParse(value);
                            if (!next.success) return;
                            setKind(next.data);
                            setOlder(null);
                        }}
                    >
                        <TabsList>
                            <TabsTrigger value="accepted" disabled={busy}>
                                Friends
                            </TabsTrigger>
                            <TabsTrigger value="incoming" disabled={busy}>
                                Requests
                                {friends.data?.incoming_count
                                    ? ` (${friends.data.incoming_count})`
                                    : ""}
                            </TabsTrigger>
                            <TabsTrigger value="outgoing" disabled={busy}>
                                Sent
                            </TabsTrigger>
                        </TabsList>
                    </Tabs>
                </CardAction>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                <form
                    onSubmit={(event) => {
                        event.preventDefault();
                        run(async () => {
                            setFound(null);
                            setFound(
                                await fitfightApi(
                                    `profiles/lookup?handle=${encodeURIComponent(handle.trim())}`,
                                    sharedIdentitySchema,
                                ),
                            );
                        });
                    }}
                >
                    <InputGroup>
                        <InputGroupAddon>
                            <SearchIcon />
                        </InputGroupAddon>
                        <InputGroupInput
                            placeholder="Add a friend by username"
                            autoCapitalize="none"
                            autoCorrect="off"
                            value={handle}
                            onChange={(event) => setHandle(event.target.value)}
                        />
                        {handle.trim() ? (
                            <InputGroupAddon align="inline-end">
                                <InputGroupButton type="submit" disabled={busy}>
                                    Find
                                </InputGroupButton>
                            </InputGroupAddon>
                        ) : null}
                    </InputGroup>
                </form>
                {found ? <PersonRow person={found} from="lookup" /> : null}
                {error || friends.error ? (
                    <Alert variant="destructive">
                        <AlertTitle>That did not work</AlertTitle>
                        <AlertDescription>
                            {error ?? friends.error?.message}
                        </AlertDescription>
                    </Alert>
                ) : null}
                {!friends.data && !friends.error ? (
                    <Skeleton className="h-16" />
                ) : friends.data && people.length === 0 ? (
                    <Empty>
                        <EmptyHeader>
                            <EmptyMedia variant="icon">
                                <UsersIcon />
                            </EmptyMedia>
                            <EmptyTitle>No one here yet</EmptyTitle>
                            <EmptyDescription>
                                No friends or requests here yet. Search an exact
                                username to connect.
                            </EmptyDescription>
                        </EmptyHeader>
                    </Empty>
                ) : (
                    <div className="grid gap-3 md:grid-cols-2">
                        {people.map((person) => (
                            <PersonRow
                                key={person.user_id}
                                person={person}
                                from="friends"
                            >
                                {kind === "incoming" ? (
                                    <>
                                        <Button
                                            size="sm"
                                            disabled={busy}
                                            onClick={() =>
                                                respond(person, "accept")
                                            }
                                        >
                                            Accept
                                        </Button>
                                        <Button
                                            size="sm"
                                            variant="secondary"
                                            disabled={busy}
                                            onClick={() =>
                                                respond(person, "decline")
                                            }
                                        >
                                            Decline
                                        </Button>
                                    </>
                                ) : kind === "outgoing" ? (
                                    <Button
                                        size="sm"
                                        variant="secondary"
                                        disabled={busy}
                                        onClick={() =>
                                            respond(person, "remove")
                                        }
                                    >
                                        Cancel
                                    </Button>
                                ) : null}
                            </PersonRow>
                        ))}
                    </div>
                )}
            </CardContent>
            {cursor ? (
                <CardFooter>
                    <Button
                        variant="ghost"
                        disabled={busy}
                        onClick={() =>
                            run(async () => {
                                const page = await fitfightApi(
                                    `friends?kind=${kind}&cursor=${cursor}`,
                                    friendsPageSchema,
                                );
                                setOlder({
                                    ...page,
                                    people: [
                                        ...(older?.people ?? []),
                                        ...page.people,
                                    ],
                                });
                            })
                        }
                    >
                        Load more
                    </Button>
                </CardFooter>
            ) : null}
        </Card>
    );
}

function useTask() {
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);

    async function run(task: () => Promise<void>) {
        setBusy(true);
        setError(null);
        try {
            await task();
        } catch (failure) {
            setError(
                failure instanceof Error ? failure.message : String(failure),
            );
        } finally {
            setBusy(false);
        }
    }

    return { busy, error, setError, run };
}

function PersonRow({
    person,
    from,
    children,
}: {
    person: SharedIdentity;
    from: (typeof profileEntryPointValues)[number];
    children?: ReactNode;
}) {
    return (
        <div className="flex items-center gap-3">
            <Link
                href={`/app/people/${person.user_id}?from=${from}`}
                className="flex min-w-0 flex-1 items-center gap-3 rounded-lg outline-none hover:underline focus-visible:ring-3 focus-visible:ring-ring/50"
            >
                <PersonAvatar person={identityAvatar(person)} />
                <span className="flex min-w-0 flex-col">
                    <span className="truncate text-sm font-bold">
                        {person.display_name}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                        @{person.handle}
                    </span>
                </span>
            </Link>
            {children}
        </div>
    );
}

/**
 * A shared identity carries one `avatar_url`: the custom animal's art, else the photo. PersonAvatar shows the
 * stock animal first, then reads custom art from `companion_image_url`, so a photo is passed the same way.
 */
function identityAvatar(identity: SharedIdentity) {
    return {
        ...identity,
        avatar: null,
        companion_id:
            identity.companion_id ?? (identity.avatar_url ? "custom" : null),
        companion_image_url: identity.avatar_url,
    };
}

/** Same routes as the app's `changeFriendship`: remove is a DELETE, request a POST, accept and decline a respond. */
function changeFriendship(userID: string, action: FriendshipAction) {
    const path = `friends/${userID}`;
    if (action === "remove")
        return fitfightApi(path, friendshipResponseSchema, {
            method: "DELETE",
        });
    if (action === "request")
        return fitfightApi(`${path}/request`, friendshipResponseSchema, {
            body: {},
        });
    return fitfightApi(`${path}/respond`, friendshipResponseSchema, {
        body: { action },
    });
}
