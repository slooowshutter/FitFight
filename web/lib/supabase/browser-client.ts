import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { authProjects } from "@/lib/supabase/auth-projects";

/** This deployment's Supabase project (staging or production), or the Supabase CLI's local stack. */
export const ownProjectURL = z
    .string()
    .url()
    .parse(process.env.NEXT_PUBLIC_SUPABASE_URL)
    .replace(/\/$/, "");

// NOTE: The Supabase CLI's fixed local key, so `next dev` against `supabase start` can sign in.
const ownPublishableKey =
    ownProjectURL === "http://127.0.0.1:54321"
        ? "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        : Object.values(authProjects).find(
              (project) => project.url === ownProjectURL,
          )?.publishableKey;
if (!ownPublishableKey) {
    throw new Error(`No publishable key for ${ownProjectURL}`);
}

/** This deployment's login, kept in this browser like the iPhone app keeps its own. The sign-in card signs in here. */
export const ownSupabase = createClient(ownProjectURL, ownPublishableKey);

const production = authProjects.pvqntpteehdvhqyctwum;

/** Only a staging (or local) web app can switch to production; a production one already shows it. */
export const canShowProduction = ownProjectURL !== production.url;

/** Set in the admin's browser on their first visit: every visit then opens Production. */
export const productionIsDefault =
    typeof window !== "undefined" &&
    localStorage.getItem("fitfight-database") === "production";

/**
 * Production unless the admin picked Staging in this tab. Production is production's own login, minted from this one
 * by `POST /admin/production-sign-in` for the admin only, and production's own API (proxied by next.config.ts), so
 * this server never reads production data.
 */
export const showsProduction =
    canShowProduction &&
    productionIsDefault &&
    sessionStorage.getItem("fitfight-database") !== "staging";

export function showProduction(on: boolean) {
    localStorage.setItem("fitfight-database", "production");
    if (on) sessionStorage.removeItem("fitfight-database");
    else sessionStorage.setItem("fitfight-database", "staging");
    location.reload();
}

/** The project every screen reads, and its API. */
export const browserProjectURL = showsProduction
    ? production.url
    : ownProjectURL;
export const browserSupabase = showsProduction
    ? createClient(production.url, production.publishableKey)
    : ownSupabase;
export const apiBase = showsProduction ? "/api/production/v1" : "/api/v1";

// NOTE: "local" ends only this browser's session. The default ("global") would also sign out the iPhone app.
export async function signOut() {
    await ownSupabase.auth.signOut({ scope: "local" });
    if (showsProduction) await browserSupabase.auth.signOut({ scope: "local" });
}
