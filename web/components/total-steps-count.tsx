"use client";

import { useEffect, useState } from "react";

export function TotalStepsCount({ totalSteps }: { totalSteps: number }) {
    const [shown, setShown] = useState(0);

    useEffect(() => {
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            setShown(totalSteps);
            return;
        }

        const durationMs = 1800;
        let frame = 0;
        const startedAt = performance.now();
        const tick = (now: number) => {
            const progress = Math.min(1, (now - startedAt) / durationMs);
            const eased = 1 - (1 - progress) ** 3;
            setShown(Math.round(totalSteps * eased));
            if (progress < 1) {
                frame = window.requestAnimationFrame(tick);
            }
        };
        frame = window.requestAnimationFrame(tick);
        return () => window.cancelAnimationFrame(frame);
    }, [totalSteps]);

    return <>{shown.toLocaleString("en-US")}</>;
}
