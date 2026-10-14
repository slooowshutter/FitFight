"use client";

import { useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { landingCopy } from "./landing-copy";
import { Icon } from "./landing-mocks";

export function FaqSearch({ language }: { language: SiteLanguage }) {
    const text = landingCopy[language].faq;
    const [query, setQuery] = useState("");
    const search = query.trim().toLowerCase();
    const items = text.items.filter(([question, answer]) =>
        `${question} ${answer}`.toLowerCase().includes(search),
    );

    return (
        <div>
            <label className="lp-search">
                <Icon name="search" size={18} />
                <input
                    type="search"
                    value={query}
                    placeholder={text.search}
                    aria-label={text.search}
                    onChange={(event) => setQuery(event.target.value)}
                />
            </label>
            {items.length ? (
                <div className="lp-card lp-qa">
                    {items.map(([question, answer]) => (
                        <details
                            key={question}
                            open={search ? true : undefined}
                        >
                            <summary>
                                {question}
                                <i>
                                    <Icon name="plus" size={16} weight={2.4} />
                                </i>
                            </summary>
                            <p>{answer}</p>
                        </details>
                    ))}
                </div>
            ) : (
                <p className="lp-none">{text.noMatch}</p>
            )}
        </div>
    );
}
