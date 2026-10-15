/**
 * True only on `next dev` for a request whose Host is this machine. Reads the Host the browser sent (`request.url`
 * carries next dev's own address), which stops DNS rebinding from a web page. A forged Host is stopped by `npm run dev`
 * listening on 127.0.0.1 only; a server started on every interface (`next dev -H 0.0.0.0`) gives that up.
 */
export function isLocalDevRequest(request: Request): boolean {
    return (
        process.env.NODE_ENV === "development" &&
        /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(
            request.headers.get("host") ?? "",
        )
    );
}
