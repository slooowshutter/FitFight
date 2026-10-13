import type { ReactNode } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { companionPose, formatSteps, landingCopy } from "./landing-copy";

const iconPaths = {
    trophy: "M8 4h8v5a4 4 0 0 1-8 0V4Z M8 6H5.5a3 3 0 0 0 3 4.2M16 6h2.5a3 3 0 0 1-3 4.2M12 13v4M8.5 20.5h7M10 17h4",
    plusCircle:
        "M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0-17 0 M12 8.5v7M8.5 12h7",
    feed: "M7 3.5h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2Z m.5 7.5 2.8-3 2.2 2.2 1.5-1.4 2.5 2.2M5 17h14M5 20.5h9",
    bubbles:
        "M3.5 6.5A2.5 2.5 0 0 1 6 4h7.5A2.5 2.5 0 0 1 16 6.5v4a2.5 2.5 0 0 1-2.5 2.5H9l-3.5 3v-3A2.5 2.5 0 0 1 3.5 10.5v-4Z M16 8.5h2a2.5 2.5 0 0 1 2.5 2.5v4a2.5 2.5 0 0 1-1.5 2.3V20l-3-2.5h-3.5a2.5 2.5 0 0 1-2.3-1.5",
    person: "M8.2 8a3.8 3.8 0 1 0 7.6 0a3.8 3.8 0 1 0-7.6 0 M4.5 20.5c.8-3.8 3.8-5.8 7.5-5.8s6.7 2 7.5 5.8",
    personPlus:
        "M6.4 8a3.6 3.6 0 1 0 7.2 0a3.6 3.6 0 1 0-7.2 0 M3.5 20c.7-3.6 3.3-5.5 6.5-5.5 1.6 0 3 .4 4.1 1.2M18 13.5v6M15 16.5h6",
    walk: "M11.7 4.5a1.8 1.8 0 1 0 3.6 0a1.8 1.8 0 1 0-3.6 0 M9.5 21l2.2-6.2 2.8 2.7V21M7.5 12.5 10 8l4 1.2 2 3.6M10.2 8.2 11.7 14.8",
    calendar:
        "M6.5 5.5h11A2.5 2.5 0 0 1 20 8v9.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5V8a2.5 2.5 0 0 1 2.5-2.5Z M4 10h16M8.5 3.5v4M15.5 3.5v4",
    repeat: "m17 3.5 3 3-3 3 M4 11.5V10a3.5 3.5 0 0 1 3.5-3.5H20M7 20.5l-3-3 3-3 M20 12.5V14a3.5 3.5 0 0 1-3.5 3.5H4",
    lock: "M7.5 10.5h9A2.5 2.5 0 0 1 19 13v5a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 18v-5a2.5 2.5 0 0 1 2.5-2.5Z M8 10.5V8a4 4 0 0 1 8 0v2.5",
    link: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1 M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
    bell: "M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15l1.5-2Z M10 20.5a2 2 0 0 0 4 0",
    heart: "M12 20s-7.5-4.5-7.5-10A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 7.5 3c0 5.5-7.5 10-7.5 10Z",
    check: "m5 12.5 4.5 4.5L19 7.5",
    chevron: "m9.5 6 6 6-6 6",
    down: "m6 9.5 6 6 6-6",
    back: "m14.5 6-6 6 6 6",
    plus: "M12 5v14M5 12h14",
    share: "M12 3.5v11M8 7.5l4-4 4 4 M7 11H6a1.5 1.5 0 0 0-1.5 1.5v6A1.5 1.5 0 0 0 6 20h12a1.5 1.5 0 0 0 1.5-1.5v-6A1.5 1.5 0 0 0 18 11h-1",
    crown: "m4 8 4 4 4-6 4 6 4-4-1.5 10.5h-13L4 8Z",
    search: "M4.5 11a6.5 6.5 0 1 0 13 0a6.5 6.5 0 1 0-13 0 m11.5 5 4 4",
    sparkle:
        "M12 3.5 13.8 10.2 20.5 12l-6.7 1.8L12 20.5l-1.8-6.7L3.5 12l6.7-1.8L12 3.5Z",
    up: "m6 14.5 6-6 6 6",
};

export function Icon({
    name,
    size = 22,
    weight = 1.8,
}: {
    name: keyof typeof iconPaths;
    size?: number;
    weight?: number;
}) {
    return (
        <svg
            className="lp-icon"
            width={size}
            height={size}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={weight}
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
        >
            <path d={iconPaths[name]} />
        </svg>
    );
}

export function FightRow({
    fight,
    language,
}: {
    fight: (typeof landingCopy.en.fights)[number];
    language: SiteLanguage;
}) {
    const phone = landingCopy[language].phone;
    return (
        <div className="lp-fight">
            <img
                className="lp-av"
                src={`/landing/companion-${fight.rival}-avatar.webp`}
                alt=""
                width={42}
                height={42}
            />
            <div className="lp-fight-name">
                <b>{fight.name}</b>
                <small>{fight.left}</small>
            </div>
            <div
                className={
                    fight.ahead ? "lp-fight-gap" : "lp-fight-gap lp-behind"
                }
            >
                <b>{fight.gap}</b>
                <small>{fight.ahead ? phone.ahead : phone.behind}</small>
            </div>
        </div>
    );
}

export function PostCard({
    post,
    language,
}: {
    post: (typeof landingCopy.en.posts)[number];
    language: SiteLanguage;
}) {
    return (
        <article className="lp-card lp-post">
            <div className="lp-post-who">
                <img
                    className="lp-av"
                    src={`/landing/companion-${post.animal}-avatar.webp`}
                    alt=""
                    width={36}
                    height={36}
                />
                <div>
                    <b>{post.who}</b>
                    <small>{post.ago}</small>
                </div>
                <span className={post.fight ? "lp-tag lp-tag-moss" : "lp-tag"}>
                    {post.fight || landingCopy[language].phone.public}
                </span>
            </div>
            <p>{post.text}</p>
            <div className="lp-post-reacts">
                {post.reacts.map((react) => (
                    <span key={react}>{react}</span>
                ))}
                <small>{post.comments}</small>
            </div>
        </article>
    );
}

const tabIcons = ["trophy", "plusCircle", "feed", "bubbles", "person"] as const;

// The 393 x 852 design canvas, scaled with --lp-scale. Tabs only appear when the phone shows the app.
export function PhoneFrame({
    language,
    tab,
    onTab,
    children,
}: {
    language: SiteLanguage;
    tab?: number;
    onTab?: (tab: number) => void;
    children: ReactNode;
}) {
    return (
        <div className="lp-phone-wrap">
            <div className="lp-phone">
                <div className="lp-phone-status">
                    <span>9:41</span>
                    <span className="lp-phone-icons" aria-hidden="true">
                        <svg
                            width="18"
                            height="12"
                            viewBox="0 0 18 12"
                            fill="currentColor"
                        >
                            <rect x="0" y="8" width="3" height="4" rx="1" />
                            <rect x="5" y="5.5" width="3" height="6.5" rx="1" />
                            <rect x="10" y="3" width="3" height="9" rx="1" />
                            <rect x="15" y="0" width="3" height="12" rx="1" />
                        </svg>
                        <svg
                            width="26"
                            height="13"
                            viewBox="0 0 26 13"
                            fill="none"
                            stroke="currentColor"
                        >
                            <rect
                                x="0.5"
                                y="0.5"
                                width="22"
                                height="12"
                                rx="3.5"
                                opacity=".45"
                            />
                            <rect
                                x="2.5"
                                y="2.5"
                                width="16"
                                height="8"
                                rx="2"
                                fill="currentColor"
                                stroke="none"
                            />
                            <path
                                d="M24.5 4.5v4"
                                strokeLinecap="round"
                                opacity=".45"
                            />
                        </svg>
                    </span>
                </div>
                <div className="lp-phone-screen">{children}</div>
                {tab === undefined ? null : (
                    <nav className="lp-phone-tabs">
                        {landingCopy[language].phone.tabs.map(
                            (label, index) => (
                                <button
                                    key={label}
                                    type="button"
                                    className={
                                        index === tab ? "lp-on" : undefined
                                    }
                                    aria-pressed={index === tab}
                                    onClick={
                                        onTab ? () => onTab(index) : undefined
                                    }
                                    tabIndex={onTab ? undefined : -1}
                                >
                                    <i>
                                        <Icon name={tabIcons[index]} />
                                    </i>
                                    <b>{label}</b>
                                </button>
                            ),
                        )}
                    </nav>
                )}
            </div>
        </div>
    );
}

// One screen of the app per tab: Fights, New, Feed, Feedback and Profile.
export function PhoneScreen({
    tab,
    language,
    steps,
}: {
    tab: number;
    language: SiteLanguage;
    steps: number;
}) {
    const copy = landingCopy[language];
    const phone = copy.phone;
    const fox = copy.companions.animals[0];

    if (tab === 1) {
        return (
            <div className="lp-scr-new">
                <div className="lp-ph-title">{phone.newTitle}</div>
                <div className="lp-scr-new-hero">
                    <div className="lp-scr-new-tag">
                        {phone.newTagline}
                        <span>{phone.newTaglineAccent}</span>
                    </div>
                    <img
                        src="/landing/companion-fox-2.webp"
                        alt=""
                        width={146}
                        height={166}
                    />
                </div>
                <b className="lp-scr-new-q">{phone.createOrJoin}</b>
                <p className="lp-ph-cap">{phone.createOrJoinText}</p>
                <div className="lp-card lp-scr-list">
                    <div className="lp-scr-row">
                        <i>
                            <Icon name="plus" size={20} />
                        </i>
                        <div>
                            <b>{phone.create}</b>
                            <small>{phone.createText}</small>
                        </div>
                    </div>
                    <div className="lp-scr-row">
                        <i>
                            <Icon name="personPlus" size={20} />
                        </i>
                        <div>
                            <b>{phone.join}</b>
                            <small>{phone.joinText}</small>
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    if (tab === 2) {
        return (
            <div>
                <div className="lp-scr-feed-head">
                    <div className="lp-ph-title">{phone.feedTitle}</div>
                    <span className="lp-scr-plus">
                        <Icon name="plus" size={18} weight={2.4} />
                    </span>
                </div>
                {copy.posts.map((post) => (
                    <PostCard key={post.who} post={post} language={language} />
                ))}
            </div>
        );
    }

    if (tab === 3) {
        return (
            <div>
                <div className="lp-ph-title">{phone.feedbackTitle}</div>
                <div className="lp-seg lp-scr-board-seg">
                    {phone.feedbackSegments.map((segment, index) => (
                        <span
                            key={segment}
                            className={index === 0 ? "lp-on" : undefined}
                        >
                            {segment}
                        </span>
                    ))}
                </div>
                <div className="lp-card lp-scr-list">
                    {phone.requests.map(([title, kind, votes]) => (
                        <div key={title} className="lp-scr-row">
                            <span className="lp-scr-votes">
                                <Icon name="up" size={16} weight={2.4} />
                                <b>{votes}</b>
                            </span>
                            <div>
                                <b className="lp-scr-request-title">{title}</b>
                                <span
                                    className={
                                        kind === "Bug"
                                            ? "lp-tag lp-tag-ember"
                                            : "lp-tag lp-tag-moss"
                                    }
                                >
                                    {kind}
                                </span>
                            </div>
                        </div>
                    ))}
                </div>
                <span className="lp-scr-request">{phone.newRequest}</span>
            </div>
        );
    }

    if (tab === 4) {
        return (
            <div className="lp-scr-profile">
                <div className="lp-scr-me">
                    <img
                        className="lp-av"
                        src="/landing/companion-fox-avatar.webp"
                        alt=""
                        width={64}
                        height={64}
                    />
                    <div>
                        <b>Alex</b>
                        <small>@alex</small>
                        <span>{phone.copyUsername}</span>
                    </div>
                </div>
                <div className="lp-scr-companion">
                    <div>
                        <b>{fox.name}</b>
                        <small>{fox.caption}</small>
                        <span>{phone.changeAnimal}</span>
                    </div>
                    <img
                        src={`/landing/companion-fox-${companionPose(steps)}.webp`}
                        alt=""
                        width={132}
                        height={150}
                    />
                </div>
                <div className="lp-ph-eyebrow">{phone.healthEyebrow}</div>
                <div className="lp-card lp-scr-list">
                    <div className="lp-scr-row">
                        <i>
                            <Icon name="heart" size={20} />
                        </i>
                        <div>
                            <b>{phone.healthRow}</b>
                            <small>{phone.connected}</small>
                        </div>
                        <span className="lp-tag lp-tag-moss">{phone.on}</span>
                    </div>
                </div>
                <div className="lp-ph-eyebrow">{phone.settingsEyebrow}</div>
                <div className="lp-card lp-scr-list">
                    {phone.settings.map((setting) => (
                        <div key={setting} className="lp-scr-row">
                            <b>{setting}</b>
                            <Icon name="chevron" size={16} />
                        </div>
                    ))}
                </div>
            </div>
        );
    }

    return (
        <div>
            <div className="lp-scr-fights-top">
                <div>
                    <div className="lp-ph-title">{phone.fightsTitle}</div>
                    <div className="lp-scr-fights-tag">
                        {phone.tagline}
                        <span>{phone.taglineAccent}</span>
                    </div>
                    <div className="lp-ph-metric">
                        {formatSteps(steps, language)}
                    </div>
                    <div className="lp-ph-cap">{phone.stepsToday}</div>
                </div>
                <img
                    src={`/landing/companion-fox-${companionPose(steps)}.webp`}
                    alt=""
                    width={168}
                    height={192}
                />
            </div>
            <div className="lp-scr-fights-bar">
                <b>{phone.challenges}</b>
                <div className="lp-seg">
                    {phone.segments.map((segment, index) => (
                        <span
                            key={segment}
                            className={index === 0 ? "lp-on" : undefined}
                        >
                            {segment}
                        </span>
                    ))}
                </div>
            </div>
            <div className="lp-scr-fights-list">
                {copy.fights.map((fight) => (
                    <FightRow
                        key={fight.name}
                        fight={fight}
                        language={language}
                    />
                ))}
            </div>
        </div>
    );
}
