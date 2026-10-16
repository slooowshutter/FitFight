import type { ReactNode } from "react";

// NOTE: The marketing pages' unlayered styles live only here, so they never override the web app's Tailwind layers.
import "./globals.css";

export default function SiteLayout({ children }: { children: ReactNode }) {
    return children;
}
