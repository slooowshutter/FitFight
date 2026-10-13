"use client";

import { useEffect, useRef, useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { sampleTodaySteps } from "./landing-copy";
import { PhoneFrame, PhoneScreen } from "./landing-mocks";

export function LandingPhone({ language }: { language: SiteLanguage }) {
    const [tab, setTab] = useState(0);
    const [steps, setSteps] = useState(0);
    const phoneRef = useRef<HTMLDivElement>(null);

    // Count today's steps up once the phone is on screen, so the companion gets up as they grow.
    useEffect(() => {
        const phone = phoneRef.current;
        if (!phone) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            setSteps(sampleTodaySteps);
            return;
        }

        let frame = 0;
        const observer = new IntersectionObserver(
            ([entry]) => {
                if (!entry.isIntersecting) return;
                observer.disconnect();
                const startedAt = performance.now();
                const tick = (now: number) => {
                    const progress = Math.min(1, (now - startedAt) / 2200);
                    setSteps(
                        Math.round(
                            sampleTodaySteps * (1 - (1 - progress) ** 3),
                        ),
                    );
                    if (progress < 1) {
                        frame = window.requestAnimationFrame(tick);
                    }
                };
                frame = window.requestAnimationFrame(tick);
            },
            { threshold: 0.4 },
        );
        observer.observe(phone);
        return () => {
            observer.disconnect();
            window.cancelAnimationFrame(frame);
        };
    }, []);

    return (
        <div ref={phoneRef}>
            <PhoneFrame language={language} tab={tab} onTab={setTab}>
                <PhoneScreen tab={tab} language={language} steps={steps} />
            </PhoneFrame>
        </div>
    );
}
