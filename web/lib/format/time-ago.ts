/** "8 min. ago", "yesterday": the short relative time the app shows on posts and requests. */
export function timeAgo(iso: string) {
    const seconds = (Date.parse(iso) - Date.now()) / 1000;
    const [unit, size] =
        (
            [
                ["year", 31_536_000],
                ["month", 2_592_000],
                ["week", 604_800],
                ["day", 86_400],
                ["hour", 3_600],
                ["minute", 60],
            ] as const
        ).find(([, length]) => Math.abs(seconds) >= length) ??
        (["second", 1] as const);
    return new Intl.RelativeTimeFormat(undefined, {
        numeric: "auto",
        style: "short",
    }).format(Math.round(seconds / size), unit);
}
