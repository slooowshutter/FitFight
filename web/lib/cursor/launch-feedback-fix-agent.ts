import { ApiError, ERROR_CODES } from "@/lib/http";
import type {
    FeedbackMetadata,
    FeedbackPostDetail,
} from "@/lib/types/feedback/feedback";
import {
    cursorApiErrorSchema,
    cursorApiKeySchema,
    cursorCreateAgentResponseSchema,
    fitFightAgentStartingRef,
    fitFightGithubRepoUrl,
} from "@/lib/types/cursor/cloud-agent";

const CURSOR_AGENTS_URL = "https://api.cursor.com/v1/agents";
const CURSOR_LAUNCH_TIMEOUT_MS = 45_000;

function deviceSnapshot(metadata: FeedbackMetadata): string {
    return Object.keys(metadata).length === 0
        ? "none recorded"
        : JSON.stringify(metadata);
}

export async function launchFeedbackFixAgent(
    detail: FeedbackPostDetail,
    fetchImpl: typeof fetch = fetch,
    senderMetadata: FeedbackMetadata = {},
): Promise<{ agent_id: string; agent_url: string }> {
    const apiKey = cursorApiKeySchema.safeParse(process.env.CURSOR_API_KEY);
    if (!apiKey.success) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Cursor isn’t configured yet.",
        );
    }

    const userComments = detail.comments.filter((comment) => !comment.workflow_status);
    const commentBlock =
        userComments.length === 0
            ? "No comments."
            : userComments
                  .map(
                      (comment, index) =>
                          `${index + 1}. @${comment.author_handle} (${comment.created_at})\n${comment.body}\nDevice: ${deviceSnapshot(comment.metadata)}`,
                  )
                  .join("\n\n");
    let kindLabel: string;
    switch (detail.post.kind) {
        case "bug":
            kindLabel = "bug";
            break;
        case "feature":
            kindLabel = "feature request";
            break;
        default: {
            const _exhaustive: never = detail.post.kind;
            throw new Error(`Unhandled feedback kind ${_exhaustive}`);
        }
    }
    const prompt = [
        "There was a request/bug from the Bugs & requests tab. Look into it and fix it if you can.",
        "",
        `Kind: ${kindLabel}`,
        `Title: ${detail.post.title}`,
        "",
        "Post:",
        detail.post.body,
        "",
        "Attachments:",
        detail.post.media.length === 0
            ? "No attachments."
            : detail.post.media
                  .map((item, index) => {
                      const link = item.url ? ` ${item.url}` : "";
                      return `${index + 1}. ${item.original_filename} (${item.kind}, ${item.content_type})${link}`;
                  })
                  .join("\n"),
        "",
        "Device metadata:",
        deviceSnapshot(detail.post.metadata),
        "",
        "Sent to Cursor from:",
        deviceSnapshot(senderMetadata),
        "",
        "Comments, including later comments if people added more:",
        commentBlock,
    ].join("\n");

    const title = detail.post.title.trim();
    const body: Record<string, unknown> = {
        prompt: { text: prompt },
        repos: [
            {
                url: fitFightGithubRepoUrl,
                startingRef: fitFightAgentStartingRef,
            },
        ],
        autoCreatePR: true,
        skipReviewerRequest: true,
    };
    if (title) {
        body.name = title.slice(0, 100);
    }

    let response: Response;
    try {
        response = await fetchImpl(CURSOR_AGENTS_URL, {
            method: "POST",
            headers: {
                Authorization: `Basic ${Buffer.from(`${apiKey.data}:`, "utf8").toString("base64")}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(CURSOR_LAUNCH_TIMEOUT_MS),
        });
    } catch (error) {
        if (
            error instanceof Error &&
            (error.name === "TimeoutError" || error.name === "AbortError")
        ) {
            throw new ApiError(
                504,
                ERROR_CODES.internal,
                "Cursor took too long to start. Try again.",
            );
        }
        throw error;
    }

    const raw: unknown = await response.json().catch(() => null);
    if (response.status === 429) {
        throw new ApiError(
            429,
            ERROR_CODES.rate_limited,
            "Cursor is busy. Try again in a minute.",
        );
    }
    if (!response.ok) {
        const parsedError = cursorApiErrorSchema.safeParse(raw);
        const cursorCode = parsedError.success
            ? parsedError.data.code
            : undefined;
        console.error(
            "fitfight_cursor_feedback",
            JSON.stringify({
                post_id: detail.post.id,
                status: response.status,
                cursor_code: cursorCode,
            }),
        );
        if (cursorCode === "rate_limit_exceeded") {
            throw new ApiError(
                429,
                ERROR_CODES.rate_limited,
                "Cursor is busy. Try again in a minute.",
            );
        }
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            cursorLaunchMessage(
                response.status,
                parsedError.success ? parsedError.data : undefined,
            ),
            { upstream: { status: response.status, body: raw } },
        );
    }

    const parsed = cursorCreateAgentResponseSchema.safeParse(raw);
    if (!parsed.success) {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Cursor started, but the reply was missing the agent URL.",
            { upstream: { status: response.status, body: raw } },
        );
    }
    return {
        agent_id: parsed.data.agent.id,
        agent_url:
            parsed.data.agent.url ??
            `https://cursor.com/agents/${parsed.data.agent.id}`,
    };
}

function cursorLaunchMessage(
    status: number,
    error: { code: string; message: string } | undefined,
): string {
    const cursorCode = error?.code;
    if (
        status === 401 ||
        cursorCode === "unauthorized" ||
        cursorCode === "api_key_not_found"
    ) {
        return "Cursor rejected the API key on Vercel Preview.";
    }
    if (
        cursorCode === "repository_access" ||
        cursorCode === "integration_not_connected"
    ) {
        return "Cursor can’t access the FitFight GitHub repo with this API key.";
    }
    if (
        cursorCode === "plan_required" ||
        cursorCode === "usage_limit_exceeded"
    ) {
        return "Cursor’s plan or usage limit blocked this.";
    }

    const message = error?.message.trim() ?? "";
    if (
        message.length > 0 &&
        message.length <= 180 &&
        message.toLowerCase() !== "error" &&
        !/(api[_-]?key|secret|bearer|password|authorization)/i.test(message)
    ) {
        return message;
    }
    return "Could not start the Cursor agent.";
}
