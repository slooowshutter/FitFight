/**
 * True only on `next dev` for a request the web app itself sent from this machine.
 * - Host is localhost: stops DNS rebinding (`request.url` carries next dev's own address, so read the header).
 * - `Sec-Fetch-Site: same-origin`: another site open in the same browser cannot call this and read the answer,
 *   whatever the API's CORS headers say. Browsers set it and pages cannot change it.
 * - `npm run dev` listens on 127.0.0.1 only, so nobody on the network can forge either header; a server started on
 *   every interface (`next dev -H 0.0.0.0`) gives that up.
 */
export function isLocalDevRequest(request: Request): boolean {
    return (
        process.env.NODE_ENV === "development" &&
        request.headers.get("sec-fetch-site") === "same-origin" &&
        /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(
            request.headers.get("host") ?? "",
        )
    );
}
