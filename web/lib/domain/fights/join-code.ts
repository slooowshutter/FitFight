const JOIN_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ";

export function normalizeJoinCode(raw: string): string {
  return raw.replace(/[\s-]/g, "").toUpperCase();
}

export function isJoinCode(value: string): boolean {
  return /^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{4}$/.test(value);
}

export function randomJoinCode(random: () => number = Math.random): string {
  let code = "";
  for (let index = 0; index < 4; index += 1) {
    code += JOIN_CODE_ALPHABET[Math.floor(random() * JOIN_CODE_ALPHABET.length)];
  }
  return code;
}

export function rollingWindow(startsAt: string, endsAt: string): { startsAt: string; endsAt: string } {
  const startMs = Date.parse(startsAt);
  const endMs = Date.parse(endsAt);
  const durationMs = endMs - startMs;
  const nextStart = new Date(endMs);
  return {
    startsAt: nextStart.toISOString(),
    endsAt: new Date(nextStart.getTime() + durationMs).toISOString(),
  };
}
