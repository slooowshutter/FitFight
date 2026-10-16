import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { authProjects } from "@/lib/supabase/auth-projects";

/** This deployment's Supabase project (staging or production), or the Supabase CLI's local stack. */
export const browserProjectURL = z
    .string()
    .url()
    .parse(process.env.NEXT_PUBLIC_SUPABASE_URL)
    .replace(/\/$/, "");

// NOTE: The Supabase CLI's fixed local key, so `next dev` against `supabase start` can sign in.
const publishableKey =
    browserProjectURL === "http://127.0.0.1:54321"
        ? "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        : Object.values(authProjects).find(
              (project) => project.url === browserProjectURL,
          )?.publishableKey;
if (!publishableKey) {
    throw new Error(`No publishable key for ${browserProjectURL}`);
}

/** The web app's one signed-in session, kept in this browser like the iPhone app keeps its own. */
export const browserSupabase = createClient(browserProjectURL, publishableKey);

// NOTE: "local" ends only this browser's session. The default ("global") would also sign out the iPhone app.
export const signOut = () => browserSupabase.auth.signOut({ scope: "local" });
