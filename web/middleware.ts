import { NextResponse, type NextRequest } from "next/server";
import { siteLanguageSchema } from "@/lib/types/marketing/site-language";

const LANGUAGE_COOKIE = "NEXT_LOCALE";

// NOTE: Keeps the default Edge runtime. It only reads the request, and Node.js
// middleware would send every page view through the iad1 function region.
export function middleware(request: NextRequest) {
    const chosen = siteLanguageSchema.safeParse(
        request.nextUrl.searchParams.get("lang"),
    );
    if (chosen.success) {
        const url = request.nextUrl.clone();
        url.searchParams.delete("lang");
        const response = NextResponse.redirect(url);
        response.cookies.set(LANGUAGE_COOKIE, chosen.data, {
            path: "/",
            maxAge: 60 * 60 * 24 * 365,
            sameSite: "lax",
        });
        return response;
    }

    const saved = siteLanguageSchema.safeParse(
        request.cookies.get(LANGUAGE_COOKIE)?.value,
    );
    // Mirrors the app: the visitor's most preferred supported language, else English.
    const preferred = (request.headers.get("accept-language") ?? "")
        .split(",")
        .map((entry) => {
            const [tag, ...parameters] = entry.trim().toLowerCase().split(";");
            const quality = parameters.find((parameter) =>
                parameter.trim().startsWith("q="),
            );
            return {
                language: siteLanguageSchema.safeParse(tag.split("-")[0]).data,
                quality: quality ? Number(quality.trim().slice(2)) : 1,
            };
        })
        .filter((entry) => entry.language && entry.quality > 0)
        .sort((left, right) => right.quality - left.quality)[0]?.language;
    const language = saved.success ? saved.data : (preferred ?? "en");
    if (language === "en") return NextResponse.next();

    const url = request.nextUrl.clone();
    url.pathname = url.pathname === "/" ? "/fr" : `/fr${url.pathname}`;
    return NextResponse.rewrite(url);
}

export const config = {
    matcher: ["/", "/privacy", "/support", "/j/:code", "/r/:code"],
};
