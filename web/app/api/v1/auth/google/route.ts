import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { reconcileGoogleIdentity } from "@/lib/supabase/queries/google-identity-supabase-query";
import { googleIdentityRequestSchema } from "@/lib/types/auth/google-sign-in";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const body = googleIdentityRequestSchema.parse(
        await readJson(request, 32_768),
    );
    return json(
        await reconcileGoogleIdentity({
            idToken: body.id_token,
            accessToken: body.access_token,
            nonce: body.nonce,
        }),
    );
});

export const OPTIONS = corsPreflight;
