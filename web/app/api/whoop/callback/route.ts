import { after, NextResponse } from "next/server";
import { recordApiFailure } from "@/lib/observability/server-error-log";
import { finishWhoopConnection, syncWhoopUser } from "@/lib/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
// The first sync pulls the person's whole WHOOP history after the redirect.
export const maxDuration = 300;

/**
 * WHOOP sends the browser here after sign-in. The app's sign-in sheet closes on the fitfight://
 * redirect, so failures become a status instead of an error page.
 */
export async function GET(request: Request) {
    const params = new URL(request.url).searchParams;
    const code = params.get("code");
    const state = params.get("state");
    let status = "denied";
    if (code && state) {
        try {
            const userId = await finishWhoopConnection(code, state);
            status = userId ? "connected" : "error";
            if (userId) {
                after(() => syncWhoopUser(userId));
            }
        } catch (error) {
            await recordApiFailure(request, error, { params: {}, status: 502 });
            status = "error";
        }
    }
    return NextResponse.redirect(`fitfight://whoop?status=${status}`);
}
