import { createElement as h } from "react";
import { ImageResponse } from "next/og";
import type { FightImageRunner } from "@/lib/types/fight-images/fight-image";

const CELL_WIDTH = 352;
const CELL_HEIGHT = 400;
const CAPTION_HEIGHT = 90;
const COLUMNS = 4;

/**
 * One reference sheet: a white grid with one portrait per drawn runner and its caption name under it,
 * at most 16 cells. Blend matches runners by caption and look. A runner without art keeps its caption only.
 */
export async function renderReferenceSheet(runners: FightImageRunner[]): Promise<Buffer> {
    const columns = Math.min(COLUMNS, runners.length);
    const rows = Math.ceil(runners.length / columns);
    const sheet = h(
        "div",
        { style: { display: "flex", flexWrap: "wrap", width: CELL_WIDTH * columns, height: (CELL_HEIGHT + CAPTION_HEIGHT) * rows, background: "white" } },
        runners.map((runner, index) =>
            h(
                "div",
                {
                    key: index,
                    style: { display: "flex", flexDirection: "column", alignItems: "center", width: CELL_WIDTH, height: CELL_HEIGHT + CAPTION_HEIGHT },
                },
                runner.artUrl
                    ? h("img", { src: runner.artUrl, width: CELL_WIDTH - 8, height: CELL_HEIGHT - 8, style: { objectFit: "contain" } })
                    : h("div", { style: { width: CELL_WIDTH - 8, height: CELL_HEIGHT - 8 } }),
                h(
                    "div",
                    { style: { display: "flex", justifyContent: "center", textAlign: "center", width: CELL_WIDTH - 12, fontSize: 32, lineHeight: 1.15, color: "black" } },
                    runner.rosterName,
                ),
            ),
        ),
    );
    const response = new ImageResponse(sheet, {
        width: CELL_WIDTH * columns,
        height: (CELL_HEIGHT + CAPTION_HEIGHT) * rows,
    });
    return Buffer.from(await response.arrayBuffer());
}
