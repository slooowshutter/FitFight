"use client";

import { useEffect, useRef, useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";

export function TotalStepsCount({
    totalSteps,
    language,
}: {
    totalSteps: number;
    language: SiteLanguage;
}) {
    const [shown, setShown] = useState(0);
    const countRef = useRef<HTMLSpanElement>(null);

    // Count up once the number scrolls into view, so visitors see it move.
    useEffect(() => {
        const count = countRef.current;
        if (!count) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            setShown(totalSteps);
            return;
        }

        const durationMs = 1800;
        let frame = 0;
        const observer = new IntersectionObserver(
            ([entry]) => {
                if (!entry.isIntersecting) return;
                observer.disconnect();
                const startedAt = performance.now();
                const tick = (now: number) => {
                    const progress = Math.min(
                        1,
                        (now - startedAt) / durationMs,
                    );
                    const eased = 1 - (1 - progress) ** 3;
                    setShown(Math.round(totalSteps * eased));
                    if (progress < 1) {
                        frame = window.requestAnimationFrame(tick);
                    }
                };
                frame = window.requestAnimationFrame(tick);
            },
            { threshold: 0.6 },
        );
        observer.observe(count);
        return () => {
            observer.disconnect();
            window.cancelAnimationFrame(frame);
        };
    }, [totalSteps]);

    return (
        <span ref={countRef}>
            {shown.toLocaleString(language === "fr" ? "fr-FR" : "en-US")}
        </span>
    );
}
