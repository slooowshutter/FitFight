"use client";

import {
    ArchiveIcon,
    ArchiveRestoreIcon,
    ArrowBigUpIcon,
    EllipsisIcon,
    EyeOffIcon,
    FileIcon,
    FlagIcon,
    MessagesSquareIcon,
    PlusIcon,
    Trash2Icon,
} from "lucide-react";
import { type ComponentProps, useState } from "react";
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
    EmptyContent,
    EmptyDescription,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
} from "@/components/ui/empty";
import {
    Field,
    FieldDescription,
    FieldGroup,
    FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
    Select,
    SelectContent,
    SelectGroup,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import {
    Sheet,
    SheetContent,
    SheetDescription,
    SheetFooter,
    SheetHeader,
    SheetTitle,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { fitfightApi, useFitFightApi } from "@/hooks/use-fitfight-api";
import { cn } from "cn";
import { timeAgo } from "@/lib/format/time-ago";
import {
    blockFeedbackAuthorResponseSchema,
    feedbackArchiveResponseSchema,
    feedbackCommentResponseSchema,
    feedbackDetailResponseSchema,
    feedbackKindSchema,
    feedbackListResponseSchema,
    feedbackPostResponseSchema,
    feedbackSortSchema,
    feedbackSortValues,
    feedbackStatusSchema,
    feedbackVoteResponseSchema,
    reportFeedbackPostResponseSchema,
    type FeedbackKind,
    type FeedbackMetadata,
    type FeedbackPostSummary,
    type FeedbackSort,
    type FeedbackStatus,
} from "@/lib/types/feedback/feedback";
import { deletedResponseSchema } from "@/lib/types/http/deleted";

const sortLabels: Record<FeedbackSort, string> = {
    votes: "Most upvoted",
    newest: "Newest first",
    oldest: "Oldest first",
};

export default function FeedbackPage() {
    const [status, setStatus] = useState<FeedbackStatus>("open");
    const [kind, setKind] = useState<FeedbackKind | "all">("all");
    const [sort, setSort] = useState<FeedbackSort>("votes");
    const [openID, setOpenID] = useState<string | null>(null);
    const [comment, setComment] = useState("");
    const [composing, setComposing] = useState(false);
    const [draft, setDraft] = useState<{
        kind: FeedbackKind;
        title: string;
        body: string;
    }>({
        kind: "bug",
        title: "",
        body: "",
    });
    const [archiving, setArchiving] = useState<FeedbackPostSummary | null>(
        null,
    );
    const [reason, setReason] = useState("");
    const [deleting, setDeleting] = useState<FeedbackPostSummary | null>(null);
    const [busy, setBusy] = useState(false);
    const [failure, setFailure] = useState<string | null>(null);
    const list = useFitFightApi(
        `feedback?status=${status}&sort=${sort}${kind === "all" ? "" : `&kind=${kind}`}`,
        feedbackListResponseSchema,
    );
    const detail = useFitFightApi(
        openID ? `feedback/${openID}` : null,
        feedbackDetailResponseSchema,
    );
    const opened = detail.data?.post.id === openID ? detail.data : undefined;
    const openedPost =
        opened?.post ?? list.data?.posts.find((post) => post.id === openID);
    const posts = list.data?.posts ?? [];
    const filtered = status !== "open" || kind !== "all" || sort !== "votes";

    async function run(task: () => Promise<unknown>) {
        setBusy(true);
        setFailure(null);
        try {
            await task();
            list.reload();
            detail.reload();
        } catch (error) {
            setFailure(error instanceof Error ? error.message : String(error));
        } finally {
            setBusy(false);
        }
    }

    function act(
        post: FeedbackPostSummary,
        action: Parameters<ComponentProps<typeof PostMenu>["onAction"]>[0],
    ) {
        setFailure(null);
        if (action === "archive") {
            setReason("");
            setArchiving(post);
        } else if (action === "delete") {
            setDeleting(post);
        } else if (action === "report") {
            void run(() =>
                fitfightApi(
                    `feedback/${post.id}/report`,
                    reportFeedbackPostResponseSchema,
                    {
                        body: { reason: "other" },
                    },
                ),
            );
        } else {
            void run(async () => {
                await fitfightApi(
                    "feedback/blocks",
                    blockFeedbackAuthorResponseSchema,
                    {
                        body: { user_id: post.author_id },
                    },
                );
                if (openedPost?.author_id === post.author_id) setOpenID(null);
            });
        }
    }

    const vote = (post: FeedbackPostSummary) =>
        run(() =>
            fitfightApi(
                `feedback/${post.id}/vote`,
                feedbackVoteResponseSchema,
                { body: {} },
            ),
        );

    const failureAlert = failure ? (
        <Alert variant="destructive">
            <AlertTitle>That did not work</AlertTitle>
            <AlertDescription>{failure}</AlertDescription>
        </Alert>
    ) : null;

    return (
        <>
            <div className="flex items-center justify-between gap-4">
                <h1 className="text-3xl font-extrabold tracking-tight">
                    Feedback
                </h1>
                <Button
                    onClick={() => {
                        setFailure(null);
                        setComposing(true);
                    }}
                >
                    <PlusIcon data-icon="inline-start" />
                    New request
                </Button>
            </div>

            <div className="flex flex-wrap items-center gap-3">
                <Tabs
                    value={status}
                    onValueChange={(value) =>
                        setStatus(feedbackStatusSchema.parse(value))
                    }
                >
                    <TabsList>
                        <TabsTrigger value="open">Open</TabsTrigger>
                        <TabsTrigger value="archived">Archived</TabsTrigger>
                    </TabsList>
                </Tabs>
                <ToggleGroup
                    type="single"
                    variant="outline"
                    aria-label="Type"
                    value={kind}
                    onValueChange={(value) => {
                        if (value)
                            setKind(
                                value === "all"
                                    ? "all"
                                    : feedbackKindSchema.parse(value),
                            );
                    }}
                >
                    <ToggleGroupItem value="all">All</ToggleGroupItem>
                    <ToggleGroupItem value="feature">Features</ToggleGroupItem>
                    <ToggleGroupItem value="bug">Bugs</ToggleGroupItem>
                </ToggleGroup>
                <Select
                    value={sort}
                    onValueChange={(value) =>
                        setSort(feedbackSortSchema.parse(value))
                    }
                >
                    <SelectTrigger aria-label="Sort by" className="w-40">
                        <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                        <SelectGroup>
                            {feedbackSortValues.map((value) => (
                                <SelectItem key={value} value={value}>
                                    {sortLabels[value]}
                                </SelectItem>
                            ))}
                        </SelectGroup>
                    </SelectContent>
                </Select>
                {list.data ? (
                    <span className="ml-auto text-sm text-muted-foreground tabular-nums">
                        {posts.length} {posts.length === 1 ? "post" : "posts"}
                    </span>
                ) : null}
            </div>

            {list.error ? (
                <Alert variant="destructive">
                    <AlertTitle>Could not load feedback</AlertTitle>
                    <AlertDescription>{list.error.message}</AlertDescription>
                </Alert>
            ) : null}
            {failureAlert}

            {!list.data && !list.error ? (
                <div className="flex flex-col gap-3">
                    <Skeleton className="h-36" />
                    <Skeleton className="h-36" />
                    <Skeleton className="h-36" />
                </div>
            ) : list.data && posts.length === 0 ? (
                <Empty className="border">
                    <EmptyHeader>
                        <EmptyMedia variant="icon">
                            <MessagesSquareIcon />
                        </EmptyMedia>
                        <EmptyTitle>
                            {filtered
                                ? "No matching feedback"
                                : "No requests yet"}
                        </EmptyTitle>
                        <EmptyDescription>
                            {filtered
                                ? "Try changing the filters to see other feedback."
                                : "Post a bug or a feature request. Other people can upvote and comment with their username."}
                        </EmptyDescription>
                    </EmptyHeader>
                    {filtered ? null : (
                        <EmptyContent>
                            <Button onClick={() => setComposing(true)}>
                                New request
                            </Button>
                        </EmptyContent>
                    )}
                </Empty>
            ) : (
                <div className="flex flex-col gap-3">
                    {posts.map((post) => (
                        <FeedbackRow
                            key={post.id}
                            post={post}
                            canArchive={list.data?.can_archive === true}
                            busy={busy}
                            onOpen={() => {
                                setFailure(null);
                                setComment("");
                                setOpenID(post.id);
                            }}
                            onVote={() => vote(post)}
                            onAction={(action) => act(post, action)}
                        />
                    ))}
                </div>
            )}

            <Sheet
                open={openID !== null}
                onOpenChange={(open) => !open && setOpenID(null)}
            >
                <SheetContent className="w-full gap-0 data-[side=right]:sm:max-w-xl">
                    <SheetHeader className="pr-12">
                        <SheetTitle className="text-xl font-extrabold">
                            {openedPost?.title ?? "Request"}
                        </SheetTitle>
                        <SheetDescription>
                            {openedPost
                                ? `@${openedPost.author_handle} · ${timeAgo(openedPost.created_at)}`
                                : "Loading"}
                        </SheetDescription>
                    </SheetHeader>
                    <div className="flex flex-1 flex-col gap-4 overflow-y-auto px-4 pb-4">
                        {detail.error && !opened ? (
                            <Alert variant="destructive">
                                <AlertTitle>
                                    Could not load this request
                                </AlertTitle>
                                <AlertDescription>
                                    {detail.error.message}
                                </AlertDescription>
                            </Alert>
                        ) : null}
                        {failureAlert}
                        {openedPost ? (
                            <>
                                <div className="flex items-center gap-2">
                                    <Badge
                                        className={
                                            openedPost.kind === "bug"
                                                ? "bg-ember-wash text-ember-text"
                                                : "bg-moss-wash text-moss-text"
                                        }
                                    >
                                        {openedPost.kind === "bug"
                                            ? "Bug"
                                            : "Feature"}
                                    </Badge>
                                    <Button
                                        variant="outline"
                                        size="sm"
                                        aria-pressed={openedPost.voted}
                                        disabled={busy || openedPost.archived}
                                        onClick={() => vote(openedPost)}
                                        className={cn(
                                            "tabular-nums",
                                            openedPost.voted &&
                                                "bg-moss-wash text-moss-text hover:bg-moss-wash",
                                        )}
                                    >
                                        <ArrowBigUpIcon
                                            data-icon="inline-start"
                                            className={
                                                openedPost.voted
                                                    ? "fill-current"
                                                    : undefined
                                            }
                                        />
                                        {openedPost.vote_count}{" "}
                                        {openedPost.vote_count === 1
                                            ? "upvote"
                                            : "upvotes"}
                                    </Button>
                                    <div className="ml-auto">
                                        <PostMenu
                                            post={openedPost}
                                            canArchive={
                                                opened?.can_archive === true
                                            }
                                            canDelete={
                                                opened?.can_delete === true
                                            }
                                            disabled={busy}
                                            onAction={(action) =>
                                                act(openedPost, action)
                                            }
                                        />
                                    </div>
                                </div>
                                {openedPost.archived ? (
                                    <Alert>
                                        <ArchiveIcon />
                                        <AlertTitle>
                                            This feedback is archived. Votes and
                                            comments are closed.
                                        </AlertTitle>
                                        {openedPost.archive_reason ? (
                                            <AlertDescription>
                                                {openedPost.archive_reason}
                                            </AlertDescription>
                                        ) : null}
                                    </Alert>
                                ) : null}
                                <p className="text-base leading-relaxed whitespace-pre-wrap">
                                    {openedPost.body}
                                </p>
                                {openedPost.media.map((item) =>
                                    !item.url ? null : item.kind === "photo" ? (
                                        <img
                                            key={item.id}
                                            src={item.url}
                                            alt=""
                                            className="w-full rounded-xl border"
                                        />
                                    ) : item.kind === "video" ? (
                                        <video
                                            key={item.id}
                                            src={item.url}
                                            controls
                                            className="w-full rounded-xl border"
                                        />
                                    ) : (
                                        <a
                                            key={item.id}
                                            href={item.url}
                                            target="_blank"
                                            rel="noreferrer"
                                            className="flex items-center gap-2 rounded-xl border p-3 text-sm font-bold hover:bg-accent/40"
                                        >
                                            <FileIcon className="text-moss-text" />
                                            <span className="truncate">
                                                {item.original_filename}
                                            </span>
                                        </a>
                                    ),
                                )}
                                <h2 className="pt-2 text-lg font-extrabold">
                                    Comments
                                </h2>
                                {!opened ? (
                                    <Skeleton className="h-20" />
                                ) : opened.comments.length === 0 ? (
                                    <p className="text-sm text-muted-foreground">
                                        No comments yet.
                                    </p>
                                ) : (
                                    opened.comments.map((item) => (
                                        <div
                                            key={item.id}
                                            className="flex flex-col gap-1 rounded-xl border p-3"
                                        >
                                            <div className="flex items-baseline justify-between gap-2">
                                                <span className="truncate text-sm font-bold text-moss-text">
                                                    @{item.author_handle}
                                                </span>
                                                <span className="shrink-0 text-xs text-muted-foreground">
                                                    {timeAgo(item.created_at)}
                                                </span>
                                            </div>
                                            <p className="text-sm whitespace-pre-wrap">
                                                {item.body}
                                            </p>
                                        </div>
                                    ))
                                )}
                            </>
                        ) : (
                            <>
                                <Skeleton className="h-8 w-40" />
                                <Skeleton className="h-32" />
                            </>
                        )}
                    </div>
                    {openedPost && !openedPost.archived ? (
                        <SheetFooter className="border-t">
                            <form
                                onSubmit={(event) => {
                                    event.preventDefault();
                                    void run(async () => {
                                        await fitfightApi(
                                            `feedback/${openedPost.id}/comments`,
                                            feedbackCommentResponseSchema,
                                            {
                                                body: {
                                                    body: comment.trim(),
                                                    metadata: browserMetadata(),
                                                },
                                            },
                                        );
                                        setComment("");
                                    });
                                }}
                            >
                                <Field>
                                    <FieldLabel
                                        htmlFor="feedback-comment"
                                        className="sr-only"
                                    >
                                        Add a comment
                                    </FieldLabel>
                                    <Textarea
                                        id="feedback-comment"
                                        placeholder="Add a comment"
                                        maxLength={500}
                                        value={comment}
                                        onChange={(event) =>
                                            setComment(event.target.value)
                                        }
                                        className="max-h-40"
                                    />
                                    <div className="flex items-center justify-between gap-2">
                                        <FieldDescription className="tabular-nums">
                                            {comment.length}/500
                                        </FieldDescription>
                                        <Button
                                            type="submit"
                                            disabled={
                                                busy ||
                                                comment.trim().length < 2
                                            }
                                        >
                                            {busy ? (
                                                <Spinner data-icon="inline-start" />
                                            ) : null}
                                            Post
                                        </Button>
                                    </div>
                                </Field>
                            </form>
                        </SheetFooter>
                    ) : null}
                </SheetContent>
            </Sheet>

            <Dialog open={composing} onOpenChange={setComposing}>
                <DialogContent className="sm:max-w-lg">
                    <DialogHeader>
                        <DialogTitle className="text-xl font-extrabold">
                            New request
                        </DialogTitle>
                        <DialogDescription>
                            Posted with your username. Signed-in people can see
                            it, upvote, and comment.
                        </DialogDescription>
                    </DialogHeader>
                    <form
                        id="new-request"
                        onSubmit={(event) => {
                            event.preventDefault();
                            void run(async () => {
                                await fitfightApi(
                                    "feedback",
                                    feedbackPostResponseSchema,
                                    {
                                        body: {
                                            kind: draft.kind,
                                            title: draft.title.trim(),
                                            body: draft.body.trim(),
                                            metadata: browserMetadata(),
                                        },
                                    },
                                );
                                setDraft({ kind: "bug", title: "", body: "" });
                                setComposing(false);
                                setStatus("open");
                            });
                        }}
                    >
                        <FieldGroup>
                            <Field>
                                <ToggleGroup
                                    type="single"
                                    variant="outline"
                                    aria-label="Type"
                                    value={draft.kind}
                                    onValueChange={(value) => {
                                        if (value)
                                            setDraft({
                                                ...draft,
                                                kind: feedbackKindSchema.parse(
                                                    value,
                                                ),
                                            });
                                    }}
                                >
                                    <ToggleGroupItem value="bug">
                                        Bug
                                    </ToggleGroupItem>
                                    <ToggleGroupItem value="feature">
                                        Feature
                                    </ToggleGroupItem>
                                </ToggleGroup>
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="request-title">
                                    Title
                                </FieldLabel>
                                <Input
                                    id="request-title"
                                    placeholder="Short and specific"
                                    maxLength={80}
                                    value={draft.title}
                                    onChange={(event) =>
                                        setDraft({
                                            ...draft,
                                            title: event.target.value,
                                        })
                                    }
                                />
                                <FieldDescription className="tabular-nums">
                                    {draft.title.length}/80
                                </FieldDescription>
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="request-details">
                                    Details
                                </FieldLabel>
                                <Textarea
                                    id="request-details"
                                    placeholder="Describe it"
                                    maxLength={2000}
                                    value={draft.body}
                                    onChange={(event) =>
                                        setDraft({
                                            ...draft,
                                            body: event.target.value,
                                        })
                                    }
                                    className="min-h-32"
                                />
                                <FieldDescription>
                                    What happened, or what you want. Be
                                    specific.{" "}
                                    <span className="tabular-nums">
                                        {draft.body.length}/2000
                                    </span>
                                </FieldDescription>
                            </Field>
                        </FieldGroup>
                    </form>
                    {failureAlert}
                    <DialogFooter>
                        <Button
                            type="submit"
                            form="new-request"
                            disabled={
                                busy ||
                                !draft.title.trim() ||
                                !draft.body.trim()
                            }
                        >
                            {busy ? <Spinner data-icon="inline-start" /> : null}
                            Post
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={archiving !== null}
                onOpenChange={(open) => !open && setArchiving(null)}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle className="text-xl font-extrabold">
                            {archiving?.archived
                                ? "Reopen feedback"
                                : "Archive feedback"}
                        </DialogTitle>
                        <DialogDescription>
                            {archiving?.archived
                                ? "Reopen this feedback with its existing votes and discussion. People can vote and comment again."
                                : "Keep this feedback, its votes, and its discussion in Archived. New votes and comments will close. You can reopen it later."}
                        </DialogDescription>
                    </DialogHeader>
                    <p className="font-bold">{archiving?.title}</p>
                    {archiving && !archiving.archived ? (
                        <FieldGroup>
                            <Field>
                                <FieldLabel htmlFor="archive-reason">
                                    Public reason (optional)
                                </FieldLabel>
                                <Textarea
                                    id="archive-reason"
                                    maxLength={280}
                                    value={reason}
                                    onChange={(event) =>
                                        setReason(event.target.value)
                                    }
                                />
                            </Field>
                        </FieldGroup>
                    ) : null}
                    {failureAlert}
                    <DialogFooter>
                        <DialogClose asChild>
                            <Button variant="outline">Cancel</Button>
                        </DialogClose>
                        <Button
                            disabled={busy}
                            onClick={() =>
                                archiving &&
                                run(async () => {
                                    await fitfightApi(
                                        `feedback/${archiving.id}`,
                                        feedbackArchiveResponseSchema,
                                        {
                                            method: "PATCH",
                                            body: {
                                                archived: !archiving.archived,
                                                reason: reason.trim(),
                                            },
                                        },
                                    );
                                    setArchiving(null);
                                })
                            }
                        >
                            {busy ? <Spinner data-icon="inline-start" /> : null}
                            {archiving?.archived
                                ? "Reopen feedback"
                                : "Archive feedback"}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={deleting !== null}
                onOpenChange={(open) => !open && setDeleting(null)}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle className="text-xl font-extrabold">
                            Delete request?
                        </DialogTitle>
                        <DialogDescription>
                            This removes the request, comments, and votes for
                            everyone. This cannot be undone.
                        </DialogDescription>
                    </DialogHeader>
                    {failureAlert}
                    <DialogFooter>
                        <DialogClose asChild>
                            <Button variant="outline">Cancel</Button>
                        </DialogClose>
                        <Button
                            variant="destructive"
                            disabled={busy}
                            onClick={() =>
                                deleting &&
                                run(async () => {
                                    await fitfightApi(
                                        `feedback/${deleting.id}`,
                                        deletedResponseSchema,
                                        {
                                            method: "DELETE",
                                        },
                                    );
                                    if (openID === deleting.id) setOpenID(null);
                                    setDeleting(null);
                                })
                            }
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

function FeedbackRow({
    post,
    canArchive,
    busy,
    onOpen,
    onVote,
    onAction,
}: {
    post: FeedbackPostSummary;
    canArchive: boolean;
    busy: boolean;
    onOpen: () => void;
    onVote: () => void;
    onAction: ComponentProps<typeof PostMenu>["onAction"];
}) {
    const photos = post.media.flatMap((item) =>
        item.kind === "photo" && item.url
            ? [{ id: item.id, url: item.url }]
            : [],
    );

    return (
        <Card>
            <CardHeader>
                <CardTitle className="text-base font-extrabold">
                    <button
                        type="button"
                        onClick={onOpen}
                        className="text-left hover:underline"
                    >
                        {post.title}
                    </button>
                </CardTitle>
                <CardDescription className="line-clamp-2">
                    {post.body}
                </CardDescription>
                <CardAction>
                    <Button
                        variant="outline"
                        aria-label="Upvote"
                        aria-pressed={post.voted}
                        disabled={busy || post.archived}
                        onClick={onVote}
                        className={cn(
                            "h-auto flex-col gap-0.5 px-3 py-1.5 font-extrabold tabular-nums",
                            post.voted &&
                                "bg-moss-wash text-moss-text hover:bg-moss-wash",
                        )}
                    >
                        <ArrowBigUpIcon
                            className={post.voted ? "fill-current" : undefined}
                        />
                        {post.vote_count}
                    </Button>
                </CardAction>
            </CardHeader>
            {photos.length > 0 ? (
                <CardContent className="flex gap-2">
                    {photos.slice(0, 4).map((photo) => (
                        <img
                            key={photo.id}
                            src={photo.url}
                            alt=""
                            className="size-12 rounded-lg border object-cover"
                        />
                    ))}
                </CardContent>
            ) : null}
            <CardFooter className="gap-2 py-2 text-xs text-muted-foreground">
                <Badge
                    className={
                        post.kind === "bug"
                            ? "bg-ember-wash text-ember-text"
                            : "bg-moss-wash text-moss-text"
                    }
                >
                    {post.kind === "bug" ? "Bug" : "Feature"}
                </Badge>
                {post.archived ? (
                    <Badge variant="outline">Archived</Badge>
                ) : null}
                <span className="truncate">@{post.author_handle}</span>
                <span>·</span>
                <button
                    type="button"
                    onClick={onOpen}
                    className="shrink-0 hover:text-foreground hover:underline"
                >
                    {post.comment_count === 1
                        ? "1 comment"
                        : `${post.comment_count} comments`}
                </button>
                <span>·</span>
                <span className="shrink-0">{timeAgo(post.created_at)}</span>
                <div className="ml-auto">
                    <PostMenu
                        post={post}
                        canArchive={canArchive}
                        canDelete={post.mine || canArchive}
                        disabled={busy}
                        onAction={onAction}
                    />
                </div>
            </CardFooter>
        </Card>
    );
}

function PostMenu({
    post,
    canArchive,
    canDelete,
    disabled,
    onAction,
}: {
    post: FeedbackPostSummary;
    canArchive: boolean;
    canDelete: boolean;
    disabled: boolean;
    onAction: (action: "report" | "hide" | "archive" | "delete") => void;
}) {
    if (post.mine && !canArchive && !canDelete) return null;
    return (
        <DropdownMenu>
            <DropdownMenuTrigger asChild>
                <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label="More"
                    disabled={disabled}
                >
                    <EllipsisIcon />
                </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
                <DropdownMenuGroup>
                    {post.mine ? null : (
                        <>
                            <DropdownMenuItem
                                onSelect={() => onAction("report")}
                            >
                                <FlagIcon />
                                Report
                            </DropdownMenuItem>
                            <DropdownMenuItem
                                variant="destructive"
                                onSelect={() => onAction("hide")}
                            >
                                <EyeOffIcon />
                                Hide this person
                            </DropdownMenuItem>
                        </>
                    )}
                    {canArchive ? (
                        <DropdownMenuItem onSelect={() => onAction("archive")}>
                            {post.archived ? (
                                <ArchiveRestoreIcon />
                            ) : (
                                <ArchiveIcon />
                            )}
                            {post.archived
                                ? "Reopen feedback"
                                : "Archive feedback"}
                        </DropdownMenuItem>
                    ) : null}
                    {canDelete ? (
                        <DropdownMenuItem
                            variant="destructive"
                            onSelect={() => onAction("delete")}
                        >
                            <Trash2Icon />
                            Delete request
                        </DropdownMenuItem>
                    ) : null}
                </DropdownMenuGroup>
            </DropdownMenuContent>
        </DropdownMenu>
    );
}

/** The app's FitFightFeedbackMetadata.current(), describing this browser instead of an iPhone. */
function browserMetadata(): FeedbackMetadata {
    const resolved = Intl.DateTimeFormat(undefined, {
        hour: "numeric",
    }).resolvedOptions();
    return {
        os: "web",
        user_agent: navigator.userAgent,
        language: navigator.language.split("-")[0],
        preferred_languages: navigator.languages.slice(0, 8),
        locale: resolved.locale,
        region: new Intl.Locale(resolved.locale).region,
        time_zone: resolved.timeZone,
        calendar: resolved.calendar,
        hour_cycle: resolved.hour12 ? "12" : "24",
        appearance: matchMedia("(prefers-color-scheme: dark)").matches
            ? "dark"
            : "light",
        layout_direction: document.dir === "rtl" ? "rtl" : "ltr",
        reduce_motion: matchMedia("(prefers-reduced-motion: reduce)").matches,
        increase_contrast: matchMedia("(prefers-contrast: more)").matches,
        screen_scale: devicePixelRatio,
        screen_width: screen.width,
        screen_height: screen.height,
    };
}
