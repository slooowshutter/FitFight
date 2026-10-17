"use client";

import { PlusIcon, SwordsIcon, XIcon } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { z } from "zod";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
    Card,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog";
import {
    Field,
    FieldContent,
    FieldDescription,
    FieldError,
    FieldGroup,
    FieldLabel,
    FieldSeparator,
    FieldTitle,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
    InputGroup,
    InputGroupAddon,
    InputGroupButton,
    InputGroupInput,
} from "@/components/ui/input-group";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { isJoinCode } from "@/lib/domain/fights/join-code";
import { useMe } from "@/components/web-app/web-app-shell";
import {
    FitFightApiError,
    fitfightApi,
    useFitFightApi,
} from "@/hooks/use-fitfight-api";
import type { createFightSchema } from "@/lib/types/fights/create-fight";
import { fightSummaryResponseSchema } from "@/lib/types/fights/fight-summary";
import { fightVisibilityValues } from "@/lib/types/fights/fight-visibility";
import type { FightJoinStart } from "@/lib/types/fights/join-start";
import {
    joinableFightListResponseSchema,
    joinableFightSummarySchema,
    type FightVisibility,
    type JoinableFightSummary,
} from "@/lib/types/fights/joinable-fight";

const durations = [
    { value: "3", label: "3 days" },
    { value: "7", label: "1 week" },
    { value: "14", label: "2 weeks" },
    { value: "30", label: "1 month" },
    { value: "custom", label: "Custom" },
];

const stamp = { dateStyle: "medium", timeStyle: "short" } as const;

/** Milliseconds `timeZone` is ahead of UTC at `instant`, so wall times follow the fight's zone like the app's calendar. */
function zoneOffset(instant: number, timeZone: string) {
    const wall = new Intl.DateTimeFormat("sv-SE", {
        timeZone,
        dateStyle: "short",
        timeStyle: "medium",
    }).format(instant);
    return (
        Date.parse(`${wall.replace(" ", "T")}Z`) -
        Math.floor(instant / 1000) * 1000
    );
}

/** The instant of a `datetime-local` wall time read in `timeZone`. */
function wallInstant(wall: string, timeZone: string) {
    const guess = Date.parse(`${wall}Z`);
    if (Number.isNaN(guess)) return guess;
    return guess - zoneOffset(guess - zoneOffset(guess, timeZone), timeZone);
}

export default function NewFightPage() {
    return (
        <>
            <h1 className="text-3xl font-extrabold tracking-tight">
                New fight
            </h1>
            <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
                <CreateFightCard />
                <JoinFightColumn />
            </div>
        </>
    );
}

function CreateFightCard() {
    const me = useMe();
    const router = useRouter();
    const [timeZone, setTimeZone] = useState(
        me.time_zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone,
    );
    const [duration, setDuration] = useState("7");
    const [customWindow, setCustomWindow] = useState(() => {
        const start = Math.ceil(Date.now() / 60_000) * 60_000 + 3_600_000;
        return [start, start + 7 * 86_400_000].map((instant) =>
            new Date(instant + zoneOffset(instant, timeZone))
                .toISOString()
                .slice(0, 16),
        );
    });
    const [recurring, setRecurring] = useState(true);
    const [visibility, setVisibility] =
        useState<FightVisibility>("invite_only");
    const [username, setUsername] = useState("");
    const [usernameError, setUsernameError] = useState<string | null>(null);
    const [handles, setHandles] = useState<string[]>([]);
    const [title, setTitle] = useState("");
    const [action, setAction] = useState("");
    const [creating, setCreating] = useState(false);
    const [createError, setCreateError] = useState<string | null>(null);

    const custom = duration === "custom";
    const label =
        durations.find((option) => option.value === duration)?.label ?? "";
    const presetWindow = (start: number) => {
        const end = start + Number(duration) * 86_400_000;
        return [
            start,
            end + zoneOffset(start, timeZone) - zoneOffset(end, timeZone),
        ];
    };
    const now = Date.now();
    const [startsAt, endsAt] = custom
        ? customWindow.map((wall) => wallInstant(wall, timeZone))
        : presetWindow(now);
    const scheduleError = !custom
        ? null
        : !(startsAt > now)
          ? "Choose a start time in the future."
          : !(endsAt > startsAt)
            ? "The end must be after the start."
            : null;
    const opponents = new Intl.ListFormat("en", { type: "conjunction" }).format(
        handles.map((handle) => `@${handle}`),
    );

    const addUsername = (input: string) => {
        const handle = input
            .trim()
            .replace(/^@+|@+$/g, "")
            .toLowerCase();
        if (!/^[a-z0-9_]{2,30}$/.test(handle)) {
            setUsernameError("Use 2-30 letters, numbers, or underscores.");
        } else if (handle === me.handle) {
            setUsernameError("Add someone else’s username.");
        } else if (handles.includes(handle)) {
            setUsernameError(`@${handle} is already in this fight.`);
        } else {
            setHandles([...handles, handle]);
            setUsername("");
            setUsernameError(null);
        }
    };

    // Profile's Challenge button opens this page with the opponent's username.
    useEffect(() => {
        const handle = new URLSearchParams(window.location.search).get(
            "handle",
        );
        if (handle) {
            setUsername(handle);
            addUsername(handle);
        }
    }, []);

    const startFight = async () => {
        setCreating(true);
        setCreateError(null);
        const name = title.trim();
        const loser = action.trim();
        const [from, to] = custom
            ? [startsAt, endsAt]
            : presetWindow(Date.now());
        const body: z.input<typeof createFightSchema> = {
            name,
            startsAt: new Date(from).toISOString(),
            endsAt: new Date(to).toISOString(),
            timeZone,
            outcomeRule: "highest_total",
            goalPolicy: "shared",
            stakeKind: "action",
            actionText: loser || undefined,
            inviteHandles: handles.length > 0 ? handles : undefined,
            start: custom ? "scheduled" : "now",
            visibility,
            recurring,
        };
        try {
            const fight = await fitfightApi(
                "fights",
                fightSummaryResponseSchema,
                { body, idempotent: true },
            );
            router.push(`/app/fights/${fight.id}`);
        } catch (error) {
            setCreateError(
                error instanceof FitFightApiError &&
                    error.code === "handle_not_found"
                    ? "That username does not have a FitFight account yet."
                    : error instanceof Error
                      ? error.message
                      : "Couldn’t start the fight.",
            );
            setCreating(false);
        }
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle className="text-xl font-extrabold">Create</CardTitle>
                <CardDescription>Steps · highest total wins</CardDescription>
            </CardHeader>
            <CardContent>
                <FieldGroup>
                    <Field>
                        <FieldTitle>How long will the fight last?</FieldTitle>
                        <ToggleGroup
                            type="single"
                            aria-label="Duration"
                            variant="outline"
                            className="flex-wrap"
                            value={duration}
                            onValueChange={(value) =>
                                value && setDuration(value)
                            }
                        >
                            {durations.map((option) => (
                                <ToggleGroupItem
                                    key={option.value}
                                    value={option.value}
                                >
                                    {option.label}
                                </ToggleGroupItem>
                            ))}
                        </ToggleGroup>
                        <FieldDescription>
                            {custom
                                ? "Choose the exact start and end. Only steps inside this window count."
                                : "It starts immediately. Steps after the exact end time do not count."}
                        </FieldDescription>
                    </Field>

                    {custom ? (
                        <div className="grid gap-4 sm:grid-cols-2">
                            {["Start", "End"].map((name, index) => (
                                <Field
                                    key={name}
                                    data-invalid={
                                        scheduleError ? true : undefined
                                    }
                                >
                                    <FieldLabel htmlFor={`custom-${name}`}>
                                        {name}
                                    </FieldLabel>
                                    <Input
                                        id={`custom-${name}`}
                                        type="datetime-local"
                                        value={customWindow[index]}
                                        aria-invalid={
                                            scheduleError ? true : undefined
                                        }
                                        onChange={(event) =>
                                            setCustomWindow(
                                                customWindow.map((wall, at) =>
                                                    at === index
                                                        ? event.target.value
                                                        : wall,
                                                ),
                                            )
                                        }
                                    />
                                </Field>
                            ))}
                            <Field className="sm:col-span-2">
                                <FieldLabel htmlFor="time-zone">
                                    Time zone
                                </FieldLabel>
                                <Select
                                    value={timeZone}
                                    onValueChange={setTimeZone}
                                >
                                    <SelectTrigger
                                        id="time-zone"
                                        className="w-full"
                                    >
                                        <SelectValue />
                                    </SelectTrigger>
                                    <SelectContent
                                        position="popper"
                                        className="max-h-72"
                                    >
                                        {[
                                            ...new Set([
                                                ...Intl.supportedValuesOf(
                                                    "timeZone",
                                                ),
                                                "UTC",
                                                timeZone,
                                            ]),
                                        ]
                                            .sort()
                                            .map((zone) => (
                                                <SelectItem
                                                    key={zone}
                                                    value={zone}
                                                >
                                                    {zone.replaceAll("_", " ")}
                                                </SelectItem>
                                            ))}
                                    </SelectContent>
                                </Select>
                                <FieldError>{scheduleError}</FieldError>
                            </Field>
                        </div>
                    ) : null}

                    <Field orientation="horizontal">
                        <Checkbox
                            id="recurring"
                            checked={recurring}
                            onCheckedChange={(checked) =>
                                setRecurring(checked === true)
                            }
                        />
                        <FieldContent>
                            <FieldLabel htmlFor="recurring">
                                Repeat when it ends
                            </FieldLabel>
                            <FieldDescription>
                                The next window starts when this one ends
                            </FieldDescription>
                        </FieldContent>
                    </Field>

                    <FieldSeparator />

                    <Field>
                        <FieldTitle>Who can join?</FieldTitle>
                        <ToggleGroup
                            type="single"
                            aria-label="Who can join?"
                            variant="outline"
                            value={visibility}
                            onValueChange={(value) => {
                                const next = fightVisibilityValues.find(
                                    (option) => option === value,
                                );
                                if (next) setVisibility(next);
                            }}
                        >
                            <ToggleGroupItem value="invite_only">
                                Private
                            </ToggleGroupItem>
                            <ToggleGroupItem value="joinable">
                                Public
                            </ToggleGroupItem>
                        </ToggleGroup>
                        <FieldDescription>
                            {visibility === "joinable"
                                ? "Listed on Join. Anyone with the code or invite link can join. Usernames are optional."
                                : "New fights start private. People still join with the code or invite link. Usernames are optional."}
                        </FieldDescription>
                    </Field>

                    <Field data-invalid={usernameError ? true : undefined}>
                        <FieldLabel htmlFor="username">Username</FieldLabel>
                        <InputGroup>
                            <InputGroupInput
                                id="username"
                                placeholder="@username"
                                autoCapitalize="none"
                                autoCorrect="off"
                                spellCheck={false}
                                value={username}
                                aria-invalid={usernameError ? true : undefined}
                                onChange={(event) =>
                                    setUsername(event.target.value)
                                }
                                onKeyDown={(event) =>
                                    event.key === "Enter" &&
                                    addUsername(username)
                                }
                            />
                            <InputGroupAddon align="inline-end">
                                <InputGroupButton
                                    variant="secondary"
                                    disabled={!username.trim()}
                                    onClick={() => addUsername(username)}
                                >
                                    <PlusIcon data-icon="inline-start" />
                                    Add
                                </InputGroupButton>
                            </InputGroupAddon>
                        </InputGroup>
                        <FieldError>{usernameError}</FieldError>
                        {handles.length > 0 ? (
                            <div className="flex flex-wrap gap-2">
                                {handles.map((handle) => (
                                    <Badge
                                        key={handle}
                                        variant="secondary"
                                        className="h-7 gap-1 pr-1 text-sm"
                                    >
                                        @{handle}
                                        <Button
                                            variant="ghost"
                                            size="icon-xs"
                                            aria-label={`Remove @${handle}`}
                                            onClick={() =>
                                                setHandles(
                                                    handles.filter(
                                                        (item) =>
                                                            item !== handle,
                                                    ),
                                                )
                                            }
                                        >
                                            <XIcon />
                                        </Button>
                                    </Badge>
                                ))}
                            </div>
                        ) : null}
                    </Field>

                    <FieldSeparator />

                    {[
                        {
                            id: "title",
                            label: "Title",
                            placeholder: "Weekend walk-off",
                            value: title,
                            set: setTitle,
                            max: 120,
                        },
                        {
                            id: "action",
                            label: "Loser action",
                            placeholder: "Cook dinner",
                            value: action,
                            set: setAction,
                            max: 240,
                        },
                    ].map((field) => (
                        <Field key={field.id}>
                            <FieldLabel htmlFor={field.id}>
                                {field.label}
                            </FieldLabel>
                            {field.id === "title" ? (
                                <Input
                                    id={field.id}
                                    placeholder={field.placeholder}
                                    maxLength={field.max}
                                    value={field.value}
                                    onChange={(event) =>
                                        field.set(event.target.value)
                                    }
                                />
                            ) : (
                                <Textarea
                                    id={field.id}
                                    placeholder={field.placeholder}
                                    maxLength={field.max}
                                    rows={1}
                                    className="min-h-0 resize-none"
                                    value={field.value}
                                    onChange={(event) =>
                                        field.set(
                                            event.target.value.replace(
                                                /\n/g,
                                                "",
                                            ),
                                        )
                                    }
                                />
                            )}
                            <FieldDescription className="flex justify-between gap-4">
                                <span>
                                    {field.id === "title"
                                        ? "Required."
                                        : "Optional."}
                                </span>
                                <span className="tabular-nums">
                                    {field.value.length}/{field.max}
                                </span>
                            </FieldDescription>
                        </Field>
                    ))}

                    <div className="flex flex-col gap-1 rounded-xl bg-moss-wash p-4 text-sm">
                        <span className="font-bold">
                            You vs {opponents || "people who join"}
                        </span>
                        <span className="text-muted-foreground">
                            {custom
                                ? "Most Steps inside the selected window wins."
                                : `Most Steps wins after ${label.toLowerCase()}.`}
                        </span>
                        {scheduleError ? null : (
                            <span className="text-muted-foreground">
                                {custom
                                    ? `${new Date(startsAt).toLocaleString(undefined, { ...stamp, timeZone })} → ${new Date(endsAt).toLocaleString(undefined, { ...stamp, timeZone })}`
                                    : `Ends ${new Date(endsAt).toLocaleString(undefined, { ...stamp, timeZone })}`}{" "}
                                · {timeZone}
                            </span>
                        )}
                        <span className="text-muted-foreground">
                            {visibility === "joinable"
                                ? "Listed on Join"
                                : "Join with code or invite link"}
                        </span>
                        {recurring ? (
                            <span className="text-muted-foreground">
                                When it ends, the next window starts
                                automatically.
                            </span>
                        ) : null}
                        {action.trim() ? (
                            <span className="font-bold">
                                The loser will {action.trim()}.
                            </span>
                        ) : null}
                    </div>

                    {createError ? (
                        <Alert variant="destructive">
                            <AlertTitle>Couldn’t start the fight</AlertTitle>
                            <AlertDescription>{createError}</AlertDescription>
                        </Alert>
                    ) : null}
                </FieldGroup>
            </CardContent>
            <CardFooter>
                <Button
                    size="lg"
                    className="w-full"
                    disabled={
                        creating || scheduleError !== null || !title.trim()
                    }
                    onClick={startFight}
                >
                    {creating ? (
                        <Spinner data-icon="inline-start" />
                    ) : (
                        <SwordsIcon data-icon="inline-start" />
                    )}
                    {creating
                        ? "Starting…"
                        : custom
                          ? "Schedule fight"
                          : "Start fight"}
                </Button>
            </CardFooter>
        </Card>
    );
}

function JoinFightColumn() {
    const router = useRouter();
    const [code, setCode] = useState("");
    const [lookingUp, setLookingUp] = useState(false);
    const [codeError, setCodeError] = useState<string | null>(null);
    const [preview, setPreview] = useState<JoinableFightSummary | null>(null);
    const [joining, setJoining] = useState(false);
    const [joinError, setJoinError] = useState<string | null>(null);
    const joinable = useFitFightApi(
        "fights/joinable",
        joinableFightListResponseSchema,
    );
    const suggested = useFitFightApi(
        "fights/suggested",
        joinableFightListResponseSchema,
    );

    const openFight = (fight: JoinableFightSummary) => {
        if (fight.alreadyMember) {
            router.push(`/app/fights/${fight.fightId}`);
            return;
        }
        setJoinError(null);
        setPreview(fight);
    };

    const lookupCode = async () => {
        setLookingUp(true);
        setCodeError(null);
        try {
            openFight(
                await fitfightApi(
                    `fights/joinable/${code}`,
                    joinableFightSummarySchema,
                ),
            );
        } catch (error) {
            setCodeError(
                error instanceof Error
                    ? error.message
                    : "Couldn’t find that fight.",
            );
        }
        setLookingUp(false);
    };

    const join = async (fight: JoinableFightSummary, start: FightJoinStart) => {
        setJoining(true);
        setJoinError(null);
        try {
            const joined = await fitfightApi(
                "fights/join",
                fightSummaryResponseSchema,
                {
                    body: {
                        code: fight.joinCode,
                        fightId: fight.fightId,
                        start,
                    },
                },
            );
            router.push(`/app/fights/${joined.id}`);
        } catch (error) {
            setJoinError(
                error instanceof Error ? error.message : "Couldn’t join.",
            );
            setJoining(false);
        }
    };

    const hours = preview
        ? Math.max(
              1,
              Math.round(
                  (Date.parse(preview.endsAt) - Date.parse(preview.startsAt)) /
                      3_600_000,
              ),
          )
        : 0;
    const days = Math.max(1, Math.round(hours / 24));

    return (
        <div className="flex flex-col gap-6">
            <Card>
                <CardHeader>
                    <CardTitle className="text-xl font-extrabold">
                        Join a fight
                    </CardTitle>
                    <CardDescription>
                        Private fights join with a code or invite link. Public
                        fights also show below.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <Field data-invalid={codeError ? true : undefined}>
                        <FieldLabel htmlFor="join-code">Code</FieldLabel>
                        <InputGroup>
                            <InputGroupInput
                                id="join-code"
                                placeholder="K7M2"
                                autoComplete="off"
                                spellCheck={false}
                                className="font-bold tracking-widest uppercase"
                                value={code}
                                aria-invalid={codeError ? true : undefined}
                                onChange={(event) =>
                                    setCode(
                                        event.target.value
                                            .toUpperCase()
                                            .replace(/[^0-9A-Z]/g, "")
                                            .slice(0, 12),
                                    )
                                }
                                onKeyDown={(event) =>
                                    event.key === "Enter" &&
                                    isJoinCode(code) &&
                                    !lookingUp &&
                                    lookupCode()
                                }
                            />
                            <InputGroupAddon align="inline-end">
                                <InputGroupButton
                                    variant="default"
                                    disabled={!isJoinCode(code) || lookingUp}
                                    onClick={lookupCode}
                                >
                                    {lookingUp ? (
                                        <Spinner data-icon="inline-start" />
                                    ) : null}
                                    {lookingUp ? "Looking up…" : "Open fight"}
                                </InputGroupButton>
                            </InputGroupAddon>
                        </InputGroup>
                        <FieldError>{codeError}</FieldError>
                    </Field>
                </CardContent>
            </Card>

            {[
                {
                    title: "Live public fights",
                    list: joinable,
                    empty: "No live public fights right now. Use a code or invite link.",
                },
                {
                    title: "Suggested",
                    list: suggested,
                    empty: "No suggested fights right now.",
                },
            ].map((section) => (
                <Card key={section.title}>
                    <CardHeader>
                        <CardTitle className="font-extrabold">
                            {section.title}
                        </CardTitle>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-3">
                        {section.list.error ? (
                            <Alert variant="destructive">
                                <AlertTitle>
                                    Couldn’t load joinable fights
                                </AlertTitle>
                                <AlertDescription>
                                    {section.list.error.message}
                                </AlertDescription>
                            </Alert>
                        ) : !section.list.data ? (
                            <Skeleton className="h-14" />
                        ) : section.list.data.fights.length === 0 ? (
                            <p className="text-sm text-muted-foreground">
                                {section.empty}
                            </p>
                        ) : (
                            section.list.data.fights.map((fight) => (
                                <div
                                    key={fight.fightId}
                                    className="flex items-center gap-3"
                                >
                                    <PersonAvatar
                                        person={{
                                            display_name: "",
                                            handle: fight.ownerHandle,
                                            avatar: null,
                                            companion_id: null,
                                        }}
                                        size="sm"
                                    />
                                    <div className="flex min-w-0 flex-1 flex-col">
                                        <span className="truncate text-sm font-bold">
                                            {fight.name}
                                        </span>
                                        <span className="truncate text-xs text-muted-foreground tabular-nums">
                                            @{fight.ownerHandle} ·{" "}
                                            {fight.memberCount} in
                                            {fight.recurring
                                                ? " · repeats"
                                                : ""}{" "}
                                            · {fight.joinCode}
                                        </span>
                                    </div>
                                    {fight.alreadyMember ? (
                                        <Button
                                            variant="outline"
                                            size="sm"
                                            asChild
                                        >
                                            <Link
                                                href={`/app/fights/${fight.fightId}`}
                                            >
                                                Open fight
                                            </Link>
                                        </Button>
                                    ) : (
                                        <Button
                                            size="sm"
                                            onClick={() => openFight(fight)}
                                        >
                                            Join
                                        </Button>
                                    )}
                                </div>
                            ))
                        )}
                    </CardContent>
                </Card>
            ))}

            <Dialog
                open={preview !== null}
                onOpenChange={(open) => !open && !joining && setPreview(null)}
            >
                {preview ? (
                    <DialogContent>
                        <DialogHeader>
                            <DialogTitle className="text-xl font-extrabold">
                                {preview.name}
                            </DialogTitle>
                            <DialogDescription>
                                @{preview.ownerHandle} challenged you
                            </DialogDescription>
                        </DialogHeader>
                        <div className="flex flex-col gap-1 text-sm">
                            <span className="font-bold">
                                {hours <= 6
                                    ? `${hours} hours`
                                    : `${days} ${days === 1 ? "day" : "days"}`}{" "}
                                · Most steps wins
                            </span>
                            <span className="text-muted-foreground">
                                {new Date(preview.startsAt).toLocaleString(
                                    undefined,
                                    stamp,
                                )}{" "}
                                →{" "}
                                {new Date(preview.endsAt).toLocaleString(
                                    undefined,
                                    stamp,
                                )}
                            </span>
                            {preview.recurring ? (
                                <span className="text-muted-foreground">
                                    Repeats until you leave. Each round has its
                                    own result.
                                </span>
                            ) : null}
                            {preview.actionText &&
                            preview.actionText !== preview.name ? (
                                <span>{preview.actionText}</span>
                            ) : null}
                        </div>
                        <p className="text-xs text-muted-foreground">
                            Participants see your identity, Fight Steps,
                            standings, and posts you share in this Fight.
                            Joining does not enable profile or daily-history
                            sharing.
                        </p>
                        {preview.canJoinNext ? (
                            <div className="flex flex-col gap-2 text-sm text-muted-foreground">
                                <span>
                                    This round started{" "}
                                    {new Date(preview.startsAt).toLocaleString(
                                        undefined,
                                        stamp,
                                    )}
                                    . Join now and your steps count from that
                                    date.
                                </span>
                                <span>
                                    Or start next round, from{" "}
                                    {new Date(preview.endsAt).toLocaleString(
                                        undefined,
                                        stamp,
                                    )}
                                    .
                                </span>
                            </div>
                        ) : null}
                        {joinError ? (
                            <Alert variant="destructive">
                                <AlertTitle>Couldn’t join</AlertTitle>
                                <AlertDescription>{joinError}</AlertDescription>
                            </Alert>
                        ) : null}
                        <DialogFooter>
                            <Button
                                variant="ghost"
                                disabled={joining}
                                onClick={() => setPreview(null)}
                            >
                                Not now
                            </Button>
                            {preview.canJoinNext ? (
                                <Button
                                    variant="outline"
                                    disabled={joining}
                                    onClick={() => join(preview, "next")}
                                >
                                    Start next round
                                </Button>
                            ) : null}
                            <Button
                                disabled={joining}
                                onClick={() => join(preview, "now")}
                            >
                                {joining ? (
                                    <Spinner data-icon="inline-start" />
                                ) : null}
                                {joining
                                    ? "Joining…"
                                    : preview.canJoinNext
                                      ? "Join this round"
                                      : "Join fight"}
                            </Button>
                        </DialogFooter>
                    </DialogContent>
                ) : null}
            </Dialog>
        </div>
    );
}
