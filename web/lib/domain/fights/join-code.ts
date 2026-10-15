const JOIN_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ";

/** Existing app-wide Steps fight. Looked up at runtime; never invented. */
export const APP_WIDE_JOIN_CODE = "PGG7";

export function normalizeJoinCode(raw: string): string {
    return raw.replace(/[\s-]/g, "").toUpperCase();
}

/** Random codes use JOIN_CODE_ALPHABET; an owner may pick any 4 to 12 letters or digits. */
export function isJoinCode(value: string): boolean {
    return /^[0-9A-Z]{4,12}$/.test(value);
}

export function randomJoinCode(random: () => number = Math.random): string {
    let code = "";
    for (let index = 0; index < 4; index += 1) {
        code +=
            JOIN_CODE_ALPHABET[
                Math.floor(random() * JOIN_CODE_ALPHABET.length)
            ];
    }
    return code;
}

export function rollingWindow(
    startsAt: string,
    endsAt: string,
): { startsAt: string; endsAt: string } {
    const startMs = Date.parse(startsAt);
    const endMs = Date.parse(endsAt);
    const durationMs = endMs - startMs;
    const nextStart = new Date(endMs);
    return {
        startsAt: nextStart.toISOString(),
        endsAt: new Date(nextStart.getTime() + durationMs).toISOString(),
    };
}
