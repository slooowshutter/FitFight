import { companionCatalog } from "@/lib/domain/fight-images/catalog";
import {
    fightImageCheckSchema,
    fightImageConfiguration,
    type FightImageCastRow,
    type FightImageLayout,
    type FightImageRunner,
} from "@/lib/types/fight-images/fight-image";

const kindOrder = { custom: 1, special: 2, stock: 3 } as const;

/** Turns accepted members into runners with a caption name, description and portrait. */
export function fightImageRunners(
    rows: FightImageCastRow[],
    customNames: Map<string, string>,
): FightImageRunner[] {
    const runners = rows.map((row): FightImageRunner => {
        const custom = row.companion_id === "custom";
        // ponytail: a profile without a companion shows the default Badger in the app, so it runs as one here.
        const stock = companionCatalog[custom ? "badger" : (row.companion_id ?? "badger")] ?? companionCatalog.badger;
        return {
            userId: row.user_id,
            isOwner: row.is_owner,
            acceptedAt: row.accepted_at?.toISOString() ?? null,
            kind: custom ? "custom" : stock.kind,
            companionKey: custom ? `custom:${row.companion_image_url ?? row.user_id}` : stock.id,
            rosterName: custom ? (customNames.get(row.user_id) ?? "Custom companion") : stock.rosterName,
            description: custom ? (row.companion_prompt ?? "").replace(/\s+/g, " ").trim().slice(0, 400) : stock.description,
            artUrl: custom ? row.companion_image_url : stock.artUrl,
        };
    });
    // Two different companions must never share a caption, or the model cannot tell them apart.
    const keyByName = new Map<string, string>();
    const renamed = new Map<string, string>();
    for (const runner of runners) {
        if (renamed.has(runner.companionKey)) continue;
        let name = runner.rosterName;
        for (let suffix = 2; keyByName.has(name) && keyByName.get(name) !== runner.companionKey; suffix++)
            name = `${runner.rosterName} ${suffix}`;
        keyByName.set(name, runner.companionKey);
        renamed.set(runner.companionKey, name);
    }
    return runners.map((runner) => ({ ...runner, rosterName: renamed.get(runner.companionKey) ?? runner.rosterName }));
}

/**
 * Up to 16 runners: everyone on one straight trail. From 17: a race start with 12 featured runners in front,
 * the fight's creator first, then custom companions, then Specials, then by join order; the rest is the crowd.
 */
export function planFightImage(runners: FightImageRunner[]) {
    const ordered = [...runners].sort(
        (a, b) =>
            Number(b.isOwner) - Number(a.isOwner) ||
            kindOrder[a.kind] - kindOrder[b.kind] ||
            (a.acceptedAt ?? "").localeCompare(b.acceptedAt ?? "") ||
            a.userId.localeCompare(b.userId),
    );
    const layout: FightImageLayout = runners.length >= fightImageConfiguration.raceStartFrom ? "race_start" : "trail";
    const drawn = layout === "trail" ? ordered : ordered.slice(0, fightImageConfiguration.featured);
    const tally = (list: FightImageRunner[]) => {
        const counts = new Map<string, { runner: FightImageRunner; count: number }>();
        for (const runner of list) {
            const entry = counts.get(runner.rosterName);
            if (entry) entry.count++;
            else counts.set(runner.rosterName, { runner, count: 1 });
        }
        return [...counts.values()];
    };
    const drawnTally = tally(drawn);
    const crowd = tally(ordered.slice(drawn.length)).sort((a, b) => b.count - a.count);
    return {
        layout,
        // Identical companions sit next to each other on the reference sheet.
        sheet: drawnTally.flatMap(({ runner, count }) => Array.from({ length: count }, () => runner)),
        roster: [
            `Total characters: ${drawn.length}`,
            ...drawnTally.map(
                ({ runner, count }) =>
                    `${runner.rosterName}${count > 1 ? ` (x${count})` : ""}: ${runner.description}`,
            ),
        ].join("\n"),
        expected: Object.fromEntries(drawnTally.map(({ runner, count }) => [runner.rosterName, count])),
        crowdSize: ordered.length - drawn.length,
        crowdCompanions: crowd.map(({ runner, count }) => `${runner.rosterName} x${count}`).join(", "),
    };
}

/**
 * Reads the Blend count check. A trail image needs every runner the right number of times and nothing extra.
 * In a race start a plain crowd animal looks exactly like a featured one, so each featured runner only has to
 * be there. Nobody may face left.
 */
export function judgeFightImage(layout: FightImageLayout, expected: Record<string, number>, checkText: string) {
    const match = checkText.match(/\{[\s\S]*\}/);
    let raw: unknown = null;
    try {
        raw = match ? JSON.parse(match[0]) : null;
    } catch {
        raw = null;
    }
    const parsed = fightImageCheckSchema.safeParse(raw);
    if (!parsed.success) return { pass: false, problems: ["unreadable check"] };
    const check = parsed.data;
    const seen = new Map<string, number>();
    for (const { name, count } of check.counts) {
        const key = name.replace(/\s*\(x\d+\)\s*$/, "").trim().toLowerCase();
        seen.set(key, (seen.get(key) ?? 0) + count);
    }
    const problems: string[] = [];
    for (const [name, count] of Object.entries(expected)) {
        const got = seen.get(name.toLowerCase()) ?? 0;
        if (layout === "trail" ? got !== count : got < 1) problems.push(`${name}: expected ${count}, saw ${got}`);
        seen.delete(name.toLowerCase());
    }
    if (layout === "trail") {
        const total = Object.values(expected).reduce((sum, count) => sum + count, 0);
        for (const [name, count] of seen) if (count > 0) problems.push(`${name}: not in the fight, saw ${count}`);
        if (check.unknown > 0) problems.push(`unknown runners: ${check.unknown}`);
        if (check.total !== total) problems.push(`total: expected ${total}, saw ${check.total}`);
    }
    if (check.facing_left > 0) problems.push(`facing left: ${check.facing_left}`);
    return { pass: problems.length === 0, problems };
}
