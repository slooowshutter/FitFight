import type { Metadata } from "next";
import type { ReactNode } from "react";
import { TooltipProvider } from "@/components/ui/tooltip";
import { WebAppShell } from "@/components/web-app/web-app-shell";

import "./app.css";

export const metadata: Metadata = {
    title: "FitFight",
    robots: { index: false, follow: false },
};

export default function WebAppLayout({ children }: { children: ReactNode }) {
    return (
        <TooltipProvider>
            <WebAppShell>{children}</WebAppShell>
        </TooltipProvider>
    );
}
