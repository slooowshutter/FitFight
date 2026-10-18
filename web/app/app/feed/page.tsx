"use client";

import {
    EllipsisIcon,
    HeartIcon,
    MessageCircleIcon,
    NewspaperIcon,
    PlusIcon,
    SendIcon,
    XIcon,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
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
import { Checkbox } from "@/components/ui/checkbox";
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
    FieldGroup,
    FieldLabel,
    FieldLegend,
    FieldSet,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
    InputGroup,
    InputGroupAddon,
    InputGroupButton,
    InputGroupTextarea,
} from "@/components/ui/input-group";
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from "@/components/ui/popover";
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
import { Textarea } from "@/components/ui/textarea";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { useMe } from "@/components/web-app/web-app-shell";
import { fitfightApi, useFitFightApi } from "@/hooks/use-fitfight-api";
import { webFights } from "@/lib/domain/fights/web-fight-view";
import { timeAgo } from "@/lib/format/time-ago";
import {
    type FeedDestination,
    type FightPost,
    type FightPostComment,
    type FightPostListResponse,
    deleteFightPostCommentResponseSchema,
    fightPostBatchResponseSchema,
    fightPostCommentLikeResponseSchema,
    fightPostCommentListResponseSchema,
    fightPostCommentResponseSchema,
    fightPostListResponseSchema,
    fightPostReactionResponseSchema,
    fightPostResponseSchema,
    reportFightPostCommentResponseSchema,
    reportFightPostResponseSchema,
} from "@/lib/types/feed/fight-post";
import { fightSnapshotSchema } from "@/lib/types/fights/fight-snapshot";
import { deletedResponseSchema } from "@/lib/types/http/deleted";

const quickEmoji = ["🔥", "💪", "😂", "❤️", "👏", "😮"];

export default function FeedPage() {
    const [feed, setFeed] = useState<FightPostListResponse | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [loadingMore, setLoadingMore] = useState(false);
    const [composing, setComposing] = useState(false);
    const [thread, setThread] = useState<{ id: string; open: boolean } | null>(
        null,
    );
    const threadPost = feed?.posts.find((post) => post.id === thread?.id);

    function load(cursor?: string | null) {
        return fitfightApi(
            `feed?limit=10${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`,
            fightPostListResponseSchema,
        ).then(
            (page) => {
                setFeed((previous) =>
                    cursor && previous
                        ? {
                              posts: [
                                  ...previous.posts,
                                  ...page.posts.filter(
                                      (post) =>
                                          !previous.posts.some(
                                              (shown) => shown.id === post.id,
                                          ),
                                  ),
                              ],
                              next_cursor: page.next_cursor,
                          }
                        : page,
                );
                setError(null);
            },
            (failure: Error) => setError(failure.message),
        );
    }

    function updatePost(id: string, update: Partial<FightPost>) {
        setFeed(
            (previous) =>
                previous && {
                    ...previous,
                    posts: previous.posts.map((post) =>
                        post.id === id ? { ...post, ...update } : post,
                    ),
                },
        );
    }

    useEffect(() => {
        load();
    }, []);

    return (
        <div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
            <div className="flex items-center justify-between gap-4">
                <div className="flex flex-col gap-1">
                    <h1 className="text-3xl font-extrabold tracking-tight">
                        Feed
                    </h1>
                    <p className="text-muted-foreground">
                        Posts from fights you’re in.
                    </p>
                </div>
                <Button onClick={() => setComposing(true)}>
                    <PlusIcon data-icon="inline-start" />
                    New post
                </Button>
            </div>

            {error ? (
                <Alert variant="destructive">
                    <AlertTitle>Something went wrong</AlertTitle>
                    <AlertDescription>{error}</AlertDescription>
                </Alert>
            ) : null}

            {!feed && !error ? (
                <>
                    <Skeleton className="h-48" />
                    <Skeleton className="h-48" />
                </>
            ) : feed && feed.posts.length === 0 ? (
                <Empty className="border">
                    <EmptyHeader>
                        <EmptyMedia variant="icon">
                            <NewspaperIcon />
                        </EmptyMedia>
                        <EmptyTitle>Nothing here yet</EmptyTitle>
                        <EmptyDescription>
                            Post a note or some proof to your fights.
                        </EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent>
                        <Button onClick={() => setComposing(true)}>
                            New post
                        </Button>
                    </EmptyContent>
                </Empty>
            ) : (
                feed?.posts.map((post) => (
                    <PostCard
                        key={post.id}
                        post={post}
                        onChange={(update) => updatePost(post.id, update)}
                        onRemove={() =>
                            setFeed(
                                (previous) =>
                                    previous && {
                                        ...previous,
                                        posts: previous.posts.filter(
                                            (shown) => shown.id !== post.id,
                                        ),
                                    },
                            )
                        }
                        onOpenComments={() =>
                            setThread({ id: post.id, open: true })
                        }
                        onError={setError}
                    />
                ))
            )}

            {feed?.next_cursor ? (
                <Button
                    variant="outline"
                    disabled={loadingMore}
                    onClick={() => {
                        setLoadingMore(true);
                        load(feed.next_cursor).finally(() =>
                            setLoadingMore(false),
                        );
                    }}
                >
                    {loadingMore ? <Spinner data-icon="inline-start" /> : null}
                    Load more
                </Button>
            ) : null}

            <ComposeDialog
                open={composing}
                onOpenChange={setComposing}
                onPosted={() => load()}
            />
            {thread && threadPost ? (
                <PostThread
                    key={thread.id}
                    post={threadPost}
                    open={thread.open}
                    onOpenChange={(open) => setThread({ id: thread.id, open })}
                    onChange={(update) => updatePost(thread.id, update)}
                />
            ) : null}
        </div>
    );
}

function PostCard({
    post,
    onChange,
    onRemove,
    onOpenComments,
    onError,
}: {
    post: FightPost;
    onChange: (update: Partial<FightPost>) => void;
    onRemove: () => void;
    onOpenComments: () => void;
    onError: (message: string) => void;
}) {
    const [reacting, setReacting] = useState(false);
    const [emojiOpen, setEmojiOpen] = useState(false);
    const [customEmoji, setCustomEmoji] = useState("");
    const [draft, setDraft] = useState<string | null>(null);
    const [saving, setSaving] = useState(false);
    const [editError, setEditError] = useState<string | null>(null);
    const [confirmDelete, setConfirmDelete] = useState(false);
    const [reported, setReported] = useState(false);
    const ranked = post.reactions
        .toSorted(
            (left, right) =>
                right.count - left.count || (left.emoji < right.emoji ? -1 : 1),
        )
        .map((reaction) => reaction.emoji);
    const custom =
        [...new Intl.Segmenter().segment(customEmoji.trim())][0]?.segment ?? "";
    const channel =
        post.to_friends && !post.broadcast && post.channels.length === 0
            ? "Friends"
            : post.broadcast || post.audience === "main"
            ? "Public"
            : post.channels
                  .filter((item) => item.name)
                  .map((item) => item.name)
                  .join(" · ") || post.fight_name;

    function react(emoji: string) {
        setReacting(true);
        fitfightApi(
            `posts/${post.id}/reactions`,
            fightPostReactionResponseSchema,
            { body: { emoji } },
        )
            .then(
                ({ reactions }) => onChange({ reactions }),
                (failure: Error) => onError(failure.message),
            )
            .finally(() => setReacting(false));
    }

    return (
        <Card>
            <CardHeader>
                <div className="flex min-w-0 items-center gap-3">
                    <Link href={`/app/people/${post.author.user_id}`}>
                        <PersonAvatar person={post.author} size="lg" />
                    </Link>
                    <div className="flex min-w-0 flex-col gap-0.5">
                        <CardTitle className="truncate font-extrabold">
                            <Link
                                href={`/app/people/${post.author.user_id}`}
                                className="hover:underline"
                            >
                                {post.author.display_name}
                            </Link>
                        </CardTitle>
                        <CardDescription className="truncate">
                            @{post.author.handle} ·{" "}
                            {post.fight_id ? (
                                <Link
                                    href={`/app/fights/${post.fight_id}`}
                                    className="hover:underline"
                                >
                                    {channel}
                                </Link>
                            ) : (
                                channel
                            )}{" "}
                            · {timeAgo(post.created_at)}
                        </CardDescription>
                    </div>
                </div>
                <CardAction>
                    <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                            <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Post actions"
                            >
                                <EllipsisIcon />
                            </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                            {post.mine ? (
                                <>
                                    <DropdownMenuItem
                                        onSelect={() => setDraft(post.body)}
                                    >
                                        Edit
                                    </DropdownMenuItem>
                                    <DropdownMenuItem
                                        variant="destructive"
                                        onSelect={() => setConfirmDelete(true)}
                                    >
                                        Delete
                                    </DropdownMenuItem>
                                </>
                            ) : (
                                <DropdownMenuItem
                                    disabled={reported}
                                    onSelect={() =>
                                        fitfightApi(
                                            `posts/${post.id}/report`,
                                            reportFightPostResponseSchema,
                                            { body: { reason: "other" } },
                                        ).then(
                                            () => setReported(true),
                                            (failure: Error) =>
                                                onError(failure.message),
                                        )
                                    }
                                >
                                    {reported ? "Reported" : "Report"}
                                </DropdownMenuItem>
                            )}
                        </DropdownMenuContent>
                    </DropdownMenu>
                </CardAction>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
                {post.tags.length ? (
                    <p className="text-sm font-bold text-moss-text">
                        {post.tags.map((tag) => `@${tag.handle}`).join(" ")}
                    </p>
                ) : null}
                {post.body ? (
                    <p className="text-base break-words whitespace-pre-wrap">
                        {post.body}
                    </p>
                ) : null}
                {post.media.length ? (
                    <div
                        className={
                            post.media.length > 1
                                ? "grid grid-cols-2 gap-2"
                                : "grid"
                        }
                    >
                        {post.media.map((media) =>
                            !media.url ? null : media.kind === "video" ? (
                                <video
                                    key={media.id}
                                    src={media.url}
                                    controls
                                    className="max-h-96 w-full rounded-lg bg-muted"
                                />
                            ) : (
                                <a
                                    key={media.id}
                                    href={media.url}
                                    target="_blank"
                                    rel="noreferrer"
                                >
                                    <img
                                        src={media.url}
                                        alt=""
                                        className="max-h-96 w-full rounded-lg bg-muted object-cover"
                                    />
                                </a>
                            ),
                        )}
                    </div>
                ) : null}
            </CardContent>
            <CardFooter className="flex-wrap gap-1">
                {[
                    ...ranked,
                    ...quickEmoji.filter((emoji) => !ranked.includes(emoji)),
                ].map((emoji) => {
                    const reaction = post.reactions.find(
                        (item) => item.emoji === emoji,
                    );
                    return (
                        <Button
                            key={emoji}
                            size="sm"
                            variant={reaction ? "secondary" : "ghost"}
                            className={
                                reaction?.mine
                                    ? "bg-moss-wash text-moss-text hover:bg-moss-wash"
                                    : undefined
                            }
                            aria-pressed={reaction?.mine ?? false}
                            aria-label={emoji}
                            disabled={reacting}
                            onClick={() => react(emoji)}
                        >
                            {emoji}
                            {reaction ? (
                                <span className="tabular-nums">
                                    {reaction.count}
                                </span>
                            ) : null}
                        </Button>
                    );
                })}
                <Popover open={emojiOpen} onOpenChange={setEmojiOpen}>
                    <PopoverTrigger asChild>
                        <Button
                            size="icon-sm"
                            variant="ghost"
                            aria-label="Other emoji…"
                            disabled={reacting}
                        >
                            <PlusIcon />
                        </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-56">
                        <form
                            className="flex gap-2"
                            onSubmit={(event) => {
                                event.preventDefault();
                                react(custom);
                                setCustomEmoji("");
                                setEmojiOpen(false);
                            }}
                        >
                            <Input
                                aria-label="Emoji"
                                placeholder="Emoji"
                                value={customEmoji}
                                onChange={(event) =>
                                    setCustomEmoji(event.target.value)
                                }
                            />
                            <Button
                                type="submit"
                                disabled={
                                    !/\p{Extended_Pictographic}/u.test(custom)
                                }
                            >
                                React
                            </Button>
                        </form>
                    </PopoverContent>
                </Popover>
                <Button
                    variant="ghost"
                    size="sm"
                    className="ml-auto text-moss-text"
                    onClick={onOpenComments}
                >
                    <MessageCircleIcon data-icon="inline-start" />
                    {post.comment_count === 0
                        ? "Comment"
                        : post.comment_count === 1
                          ? "1 comment"
                          : `${post.comment_count} comments`}
                </Button>
            </CardFooter>

            <Dialog
                open={draft !== null}
                onOpenChange={(open) => !open && setDraft(null)}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Edit post</DialogTitle>
                    </DialogHeader>
                    <form
                        className="flex flex-col gap-4"
                        onSubmit={(event) => {
                            event.preventDefault();
                            setSaving(true);
                            fitfightApi(
                                `posts/${post.id}`,
                                fightPostResponseSchema,
                                {
                                    method: "PATCH",
                                    body: { body: (draft ?? "").trim() },
                                },
                            )
                                .then(
                                    (result) => {
                                        onChange(result.post);
                                        setDraft(null);
                                        setEditError(null);
                                    },
                                    (failure: Error) =>
                                        setEditError(failure.message),
                                )
                                .finally(() => setSaving(false));
                        }}
                    >
                        <Textarea
                            aria-label="Post"
                            placeholder="Add a note or some proof…"
                            maxLength={500}
                            rows={5}
                            value={draft ?? ""}
                            onChange={(event) => setDraft(event.target.value)}
                        />
                        {editError ? (
                            <Alert variant="destructive">
                                <AlertTitle>Could not save</AlertTitle>
                                <AlertDescription>{editError}</AlertDescription>
                            </Alert>
                        ) : null}
                        <DialogFooter>
                            <Button type="submit" disabled={saving}>
                                {saving ? "Saving…" : "Save"}
                            </Button>
                        </DialogFooter>
                    </form>
                </DialogContent>
            </Dialog>

            <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
                <DialogContent showCloseButton={false}>
                    <DialogHeader>
                        <DialogTitle>Delete this post?</DialogTitle>
                    </DialogHeader>
                    <DialogFooter>
                        <DialogClose asChild>
                            <Button variant="outline">Cancel</Button>
                        </DialogClose>
                        <Button
                            variant="destructive"
                            onClick={() =>
                                fitfightApi(
                                    `posts/${post.id}`,
                                    deletedResponseSchema,
                                    { method: "DELETE" },
                                ).then(onRemove, (failure: Error) => {
                                    setConfirmDelete(false);
                                    onError(failure.message);
                                })
                            }
                        >
                            Delete
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </Card>
    );
}

function PostThread({
    post,
    open,
    onOpenChange,
    onChange,
}: {
    post: FightPost;
    open: boolean;
    onOpenChange: (open: boolean) => void;
    onChange: (update: Partial<FightPost>) => void;
}) {
    const [comments, setComments] = useState<FightPostComment[]>([]);
    const [cursor, setCursor] = useState<string | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [draft, setDraft] = useState("");
    const [replyTo, setReplyTo] = useState<FightPostComment | null>(null);
    const [busy, setBusy] = useState<string | null>(null);
    const [reported, setReported] = useState<string[]>([]);
    const composer = useRef<HTMLTextAreaElement>(null);
    const fail = (failure: Error) => setError(failure.message);

    const newestFirst = (items: FightPostComment[]) =>
        items.toSorted(
            (left, right) =>
                Date.parse(right.created_at) - Date.parse(left.created_at) ||
                right.id.localeCompare(left.id),
        );
    const rows: { comment: FightPostComment; depth: number }[] = [];
    const visit = (comment: FightPostComment, depth: number) => {
        rows.push({ comment, depth });
        newestFirst(
            comments.filter((child) => child.parent_id === comment.id),
        ).forEach((child) => visit(child, depth + 1));
    };
    newestFirst(
        comments.filter(
            (comment) =>
                !comments.some((parent) => parent.id === comment.parent_id),
        ),
    ).forEach((comment) => visit(comment, 0));

    function loadComments(after?: string | null) {
        setLoading(true);
        return fitfightApi(
            `posts/${post.id}/comments?sort=recent${after ? `&cursor=${encodeURIComponent(after)}` : ""}`,
            fightPostCommentListResponseSchema,
        )
            .then((page) => {
                setComments((previous) =>
                    after
                        ? [
                              ...previous,
                              ...page.comments.filter(
                                  (comment) =>
                                      !previous.some(
                                          (shown) => shown.id === comment.id,
                                      ),
                              ),
                          ]
                        : page.comments,
                );
                setCursor(page.next_cursor);
            }, fail)
            .finally(() => setLoading(false));
    }

    function send() {
        if (busy === "send") return;
        const body = draft.trim();
        if (!body) return;
        setBusy("send");
        fitfightApi(
            `posts/${post.id}/comments`,
            fightPostCommentResponseSchema,
            { body: { body, parent_id: replyTo?.id } },
        )
            .then(({ comment, comment_count }) => {
                setComments((previous) => [
                    ...previous.filter((shown) => shown.id !== comment.id),
                    comment,
                ]);
                setDraft("");
                setReplyTo(null);
                setError(null);
                onChange({ comment_count });
            }, fail)
            .finally(() => setBusy(null));
    }

    useEffect(() => {
        fitfightApi(`posts/${post.id}`, fightPostResponseSchema).then(
            (result) => onChange(result.post),
            fail,
        );
        loadComments();
    }, [post.id]);

    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent className="data-[side=right]:w-full data-[side=right]:sm:max-w-lg">
                <SheetHeader>
                    <SheetTitle className="text-lg font-extrabold">
                        Comments
                    </SheetTitle>
                    <SheetDescription className="line-clamp-2">
                        {post.author.display_name}: {post.body || "Photo"}
                    </SheetDescription>
                </SheetHeader>
                <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4">
                    {error ? (
                        <Alert variant="destructive">
                            <AlertTitle>Something went wrong</AlertTitle>
                            <AlertDescription>{error}</AlertDescription>
                        </Alert>
                    ) : null}
                    {loading && comments.length === 0 ? (
                        <>
                            <Skeleton className="h-14" />
                            <Skeleton className="h-14" />
                        </>
                    ) : comments.length === 0 ? (
                        <p className="text-sm text-muted-foreground">
                            No comments yet.
                        </p>
                    ) : null}
                    {rows.map(({ comment, depth }) => (
                        <div
                            key={comment.id}
                            className={`flex gap-2 ${["", "pl-4", "pl-8", "pl-12", "pl-16"][Math.min(depth, 4)]}`}
                        >
                            <Link
                                href={`/app/people/${comment.author.user_id}`}
                            >
                                <PersonAvatar
                                    person={comment.author}
                                    size="sm"
                                />
                            </Link>
                            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                                <div className="flex items-baseline gap-2">
                                    <Link
                                        href={`/app/people/${comment.author.user_id}`}
                                        className="truncate text-sm font-bold hover:underline"
                                    >
                                        @{comment.author.handle}
                                    </Link>
                                    <span className="shrink-0 text-xs text-muted-foreground">
                                        {timeAgo(comment.created_at)}
                                    </span>
                                </div>
                                <p className="text-sm break-words whitespace-pre-wrap">
                                    {comment.body}
                                </p>
                                <div className="flex items-center gap-1">
                                    <Button
                                        variant="ghost"
                                        size="xs"
                                        onClick={() => {
                                            setReplyTo(comment);
                                            composer.current?.focus();
                                        }}
                                    >
                                        Reply
                                    </Button>
                                    <DropdownMenu>
                                        <DropdownMenuTrigger asChild>
                                            <Button
                                                variant="ghost"
                                                size="icon-xs"
                                                aria-label="Comment actions"
                                            >
                                                <EllipsisIcon />
                                            </Button>
                                        </DropdownMenuTrigger>
                                        <DropdownMenuContent align="start">
                                            {comment.mine ? (
                                                <DropdownMenuItem
                                                    variant="destructive"
                                                    onSelect={() =>
                                                        fitfightApi(
                                                            `posts/${post.id}/comments/${comment.id}`,
                                                            deleteFightPostCommentResponseSchema,
                                                            {
                                                                method: "DELETE",
                                                            },
                                                        ).then(
                                                            ({
                                                                comment_count,
                                                            }) => {
                                                                onChange({
                                                                    comment_count,
                                                                });
                                                                setReplyTo(
                                                                    null,
                                                                );
                                                                return loadComments();
                                                            },
                                                            fail,
                                                        )
                                                    }
                                                >
                                                    Delete
                                                </DropdownMenuItem>
                                            ) : (
                                                <DropdownMenuItem
                                                    disabled={reported.includes(
                                                        comment.id,
                                                    )}
                                                    onSelect={() =>
                                                        fitfightApi(
                                                            `posts/${post.id}/comments/${comment.id}/report`,
                                                            reportFightPostCommentResponseSchema,
                                                            {
                                                                body: {
                                                                    reason: "other",
                                                                },
                                                            },
                                                        ).then(
                                                            () =>
                                                                setReported(
                                                                    (
                                                                        previous,
                                                                    ) => [
                                                                        ...previous,
                                                                        comment.id,
                                                                    ],
                                                                ),
                                                            fail,
                                                        )
                                                    }
                                                >
                                                    {reported.includes(
                                                        comment.id,
                                                    )
                                                        ? "Reported"
                                                        : "Report"}
                                                </DropdownMenuItem>
                                            )}
                                        </DropdownMenuContent>
                                    </DropdownMenu>
                                </div>
                            </div>
                            <Button
                                variant="ghost"
                                size="sm"
                                className={
                                    comment.liked_by_me
                                        ? "text-moss-text"
                                        : "text-muted-foreground"
                                }
                                aria-label={
                                    comment.liked_by_me
                                        ? "Unlike comment"
                                        : "Like comment"
                                }
                                aria-pressed={comment.liked_by_me ?? false}
                                disabled={busy === comment.id}
                                onClick={() => {
                                    setBusy(comment.id);
                                    fitfightApi(
                                        `posts/${post.id}/comments/${comment.id}/like`,
                                        fightPostCommentLikeResponseSchema,
                                        {
                                            method: "PUT",
                                            body: {
                                                liked: !comment.liked_by_me,
                                            },
                                        },
                                    )
                                        .then(
                                            (like) =>
                                                setComments((previous) =>
                                                    previous.map((shown) =>
                                                        shown.id === comment.id
                                                            ? {
                                                                  ...shown,
                                                                  ...like,
                                                              }
                                                            : shown,
                                                    ),
                                                ),
                                            fail,
                                        )
                                        .finally(() => setBusy(null));
                                }}
                            >
                                <HeartIcon
                                    data-icon="inline-start"
                                    className={
                                        comment.liked_by_me
                                            ? "fill-current"
                                            : undefined
                                    }
                                />
                                {comment.like_count ? (
                                    <span className="tabular-nums">
                                        {comment.like_count}
                                    </span>
                                ) : null}
                            </Button>
                        </div>
                    ))}
                    {cursor ? (
                        <Button
                            variant="ghost"
                            size="sm"
                            className="self-start text-moss-text"
                            disabled={loading}
                            onClick={() => loadComments(cursor)}
                        >
                            More comments
                        </Button>
                    ) : null}
                </div>
                <SheetFooter>
                    <form
                        onSubmit={(event) => {
                            event.preventDefault();
                            send();
                        }}
                    >
                        <InputGroup>
                            <InputGroupTextarea
                                ref={composer}
                                aria-label="Comment"
                                placeholder={
                                    replyTo
                                        ? `Reply to @${replyTo.author.handle}…`
                                        : "Write a comment…"
                                }
                                maxLength={500}
                                value={draft}
                                onChange={(event) =>
                                    setDraft(event.target.value)
                                }
                                onKeyDown={(event) => {
                                    if (
                                        event.key === "Enter" &&
                                        !event.shiftKey &&
                                        !event.nativeEvent.isComposing
                                    ) {
                                        event.preventDefault();
                                        send();
                                    }
                                }}
                            />
                            <InputGroupAddon align="block-end">
                                {replyTo ? (
                                    <InputGroupButton
                                        onClick={() => setReplyTo(null)}
                                    >
                                        <XIcon data-icon="inline-start" />
                                        Cancel reply
                                    </InputGroupButton>
                                ) : null}
                                <InputGroupButton
                                    type="submit"
                                    variant="default"
                                    className="ml-auto"
                                    disabled={busy === "send" || !draft.trim()}
                                >
                                    {busy === "send" ? (
                                        <Spinner data-icon="inline-start" />
                                    ) : (
                                        <SendIcon data-icon="inline-start" />
                                    )}
                                    Send
                                </InputGroupButton>
                            </InputGroupAddon>
                        </InputGroup>
                    </form>
                </SheetFooter>
            </SheetContent>
        </Sheet>
    );
}

function ComposeDialog({
    open,
    onOpenChange,
    onPosted,
}: {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    onPosted: () => void;
}) {
    const me = useMe();
    const snapshot = useFitFightApi(
        open ? "fights/snapshot" : null,
        fightSnapshotSchema,
        {
            time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        },
    );
    const [body, setBody] = useState("");
    const [main, setMain] = useState(false);
    const [fightIds, setFightIds] = useState<string[]>([]);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const fights = (snapshot.data ? webFights(snapshot.data, me.user_id) : [])
        .filter((fight) => fight.status !== "invited")
        .toSorted(
            (left, right) =>
                Number(right.status === "live") -
                    Number(left.status === "live") ||
                left.fight.name.localeCompare(right.fight.name),
        )
        .filter(
            (fight, index, all) =>
                all.findIndex(
                    (other) =>
                        (other.fight.series_id ?? other.fight.id) ===
                        (fight.fight.series_id ?? fight.fight.id),
                ) === index,
        );
    const everything =
        main &&
        fights.length > 0 &&
        fights.every((fight) => fightIds.includes(fight.fight.id));

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="sm:max-w-lg">
                <DialogHeader>
                    <DialogTitle>New post</DialogTitle>
                    <DialogDescription>
                        Your post will only appear in the channels you select.
                        You can choose more than one.
                    </DialogDescription>
                </DialogHeader>
                {!snapshot.data && !snapshot.error ? (
                    <Skeleton className="h-40" />
                ) : snapshot.data && fights.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                        Join a fight first, then post from here.
                    </p>
                ) : (
                    <form
                        className="flex flex-col gap-4"
                        onSubmit={(event) => {
                            event.preventDefault();
                            const destinations: FeedDestination[] = [
                                ...(main ? [{ type: "main" as const }] : []),
                                ...fightIds.map((id) => ({
                                    type: "fight" as const,
                                    fight_id: id,
                                })),
                            ];
                            setSaving(true);
                            fitfightApi(
                                "feed/posts",
                                fightPostBatchResponseSchema,
                                {
                                    body: {
                                        body: body.trim(),
                                        media_ids: [],
                                        destinations,
                                        tagged_user_ids: [],
                                    },
                                },
                            )
                                .then(
                                    () => {
                                        setBody("");
                                        setMain(false);
                                        setFightIds([]);
                                        setError(null);
                                        onOpenChange(false);
                                        onPosted();
                                    },
                                    (failure: Error) =>
                                        setError(failure.message),
                                )
                                .finally(() => setSaving(false));
                        }}
                    >
                        <FieldGroup>
                            <Field>
                                <FieldLabel
                                    htmlFor="feed-post-body"
                                    className="sr-only"
                                >
                                    Post
                                </FieldLabel>
                                <Textarea
                                    id="feed-post-body"
                                    placeholder="Add a note or some proof…"
                                    maxLength={500}
                                    rows={4}
                                    value={body}
                                    onChange={(event) =>
                                        setBody(event.target.value)
                                    }
                                />
                            </Field>
                            <FieldSet>
                                <FieldLegend variant="label">
                                    Channels
                                </FieldLegend>
                                <FieldGroup className="gap-3">
                                    <Field orientation="horizontal">
                                        <Checkbox
                                            id="feed-post-all"
                                            checked={everything}
                                            onCheckedChange={() => {
                                                setMain(!everything);
                                                setFightIds(
                                                    everything
                                                        ? []
                                                        : fights.map(
                                                              (fight) =>
                                                                  fight.fight
                                                                      .id,
                                                          ),
                                                );
                                            }}
                                        />
                                        <FieldLabel
                                            htmlFor="feed-post-all"
                                            className="font-bold"
                                        >
                                            All fights
                                        </FieldLabel>
                                    </Field>
                                    {fights.map((fight) => (
                                        <Field
                                            key={fight.fight.id}
                                            orientation="horizontal"
                                        >
                                            <Checkbox
                                                id={`feed-post-${fight.fight.id}`}
                                                checked={fightIds.includes(
                                                    fight.fight.id,
                                                )}
                                                onCheckedChange={(checked) => {
                                                    setFightIds((previous) =>
                                                        checked
                                                            ? [
                                                                  ...previous,
                                                                  fight.fight
                                                                      .id,
                                                              ]
                                                            : previous.filter(
                                                                  (id) =>
                                                                      id !==
                                                                      fight
                                                                          .fight
                                                                          .id,
                                                              ),
                                                    );
                                                    if (!checked)
                                                        setMain(false);
                                                }}
                                            />
                                            <FieldLabel
                                                htmlFor={`feed-post-${fight.fight.id}`}
                                            >
                                                {fight.fight.name}
                                            </FieldLabel>
                                        </Field>
                                    ))}
                                </FieldGroup>
                            </FieldSet>
                        </FieldGroup>
                        {error || snapshot.error ? (
                            <Alert variant="destructive">
                                <AlertTitle>Could not post</AlertTitle>
                                <AlertDescription>
                                    {error ?? snapshot.error?.message}
                                </AlertDescription>
                            </Alert>
                        ) : null}
                        <DialogFooter>
                            <Button
                                type="submit"
                                disabled={
                                    saving ||
                                    !body.trim() ||
                                    (!main && fightIds.length === 0)
                                }
                            >
                                {saving ? "Posting…" : "Post"}
                            </Button>
                        </DialogFooter>
                    </form>
                )}
            </DialogContent>
        </Dialog>
    );
}
