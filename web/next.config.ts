import type { NextConfig } from "next";

const nextConfig: NextConfig = {
    poweredByHeader: false,
    // The admin's Production switch on a staging web app (lib/supabase/browser-client.ts): production's API on the
    // same origin, so the browser needs no CORS. The caller's production login authorizes every request there.
    async rewrites() {
        return [
            {
                source: "/api/production/v1/:path*",
                destination: "https://fitfight.app/api/v1/:path*",
            },
        ];
    },
};

export default nextConfig;
