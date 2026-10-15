import type { webFights } from "@/lib/domain/fights/web-fight-view";

/** One Fight as the web app shows it: snapshot rows joined, bucketed and ranked. */
export type WebFight = ReturnType<typeof webFights>[number];
