import { isLocalDevRequest } from "@/lib/dev/local-dev-request";
import { ApiError, ERROR_CODES, apiRoute } from "@/lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** `next dev` on localhost only: the Admin page's table pages read through the `preview` server, like its dashboard. */
export const GET = apiRoute(async (request) => {
    if (!isLocalDevRequest(request)) {
        throw new ApiError(404, ERROR_CODES.not_found, "Not found");
    }
    const response = await fetch(
        `https://fit-fight-git-preview-blendai.vercel.app/api/v1/admin/table${new URL(request.url).search}`,
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
