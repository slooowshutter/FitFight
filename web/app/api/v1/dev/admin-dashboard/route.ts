import { isLocalDevRequest } from "@/lib/dev/local-dev-request";
import { ApiError, ERROR_CODES, apiRoute } from "@/lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * `next dev` on localhost only: the web Admin page reads the dashboard through the `preview` server, as the iPhone
 * app does. Only that server holds the read-only production connection, which Vercel never lets leave.
 */
export const GET = apiRoute(async (request) => {
    if (!isLocalDevRequest(request)) {
        throw new ApiError(404, ERROR_CODES.not_found, "Not found");
    }
    const response = await fetch(
        `https://fit-fight-git-preview-blendai.vercel.app/api/v1/admin/dashboard${new URL(request.url).search}`,
        {
            headers: {
                authorization: request.headers.get("authorization") ?? "",
            },
        },
    );
    return new Response(response.body, {
        status: response.status,
        headers: { "content-type": "application/json" },
    });
});
