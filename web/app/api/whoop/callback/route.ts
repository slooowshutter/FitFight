import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * WHOOP sends the browser here after sign-in. The app's sign-in sheet closes on the fitfight://
 * redirect and posts the code with its own sign-in to /api/v1/whoop/finish, so a link opened by
 * anyone else connects nothing.
 */
export async function GET(request: Request) {
    const params = new URL(request.url).searchParams;
    const code = params.get("code");
    const state = params.get("state");
    const target = new URL("fitfight://whoop");
    if (code && state) {
        target.search = new URLSearchParams({ code, state }).toString();
    } else {
        target.searchParams.set("status", "denied");
    }
    return NextResponse.redirect(target.toString());
}
