import Link from "next/link";
import { TestflightInvite } from "@/components/testflight-invite";
import { TotalStepsCount } from "@/components/total-steps-count";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { CompanionPicker } from "./companion-picker";
import { FaqSearch } from "./faq-search";
import { FightComposerDemo } from "./fight-composer-demo";
import { formatSteps, landingCopy } from "./landing-copy";
import { FightRow, Icon, PostCard } from "./landing-mocks";
import { LandingPhone } from "./landing-phone";

const factIcons = ["walk", "lock", "check"] as const;
const optionIcons = [
    "walk",
    "calendar",
    "repeat",
    "lock",
    "link",
    "crown",
    "feed",
    "bell",
] as const;

// The fitfight.app home page ("Race Day"). Same layout in English and French.
export function LandingPage({
    language,
    download,
    totalSteps,
}: {
    language: SiteLanguage;
    download: { isStaging: boolean; url: string };
    totalSteps: number;
}) {
    const copy = landingCopy[language];
    const statement = copy.what.statement;
    const downloadButton = (kind: "header" | "hero") =>
        download.isStaging ? (
            <TestflightInvite
                label={copy.getApp}
                kind={kind}
                language={language}
            />
        ) : (
            <a
                className={
                    kind === "header" ? "header-action" : "primary-action"
                }
                href={download.url}
            >
                {kind === "header" ? copy.getApp : copy.download}
            </a>
        );

    return (
        <main className="lp" lang={language}>
            <header className="lp-header">
                <div className="lp-wrap">
                    <a
                        className="lp-brand"
                        href="#top"
                        aria-label={copy.homeLabel}
                    >
                        <img
                            src="/landing/app-icon.webp"
                            alt=""
                            width={34}
                            height={34}
                        />
                        <span>FitFight</span>
                    </a>
                    <nav className="lp-nav">
                        <a href="#how">{copy.nav.how}</a>
                        <a href="#companions">{copy.nav.companions}</a>
                        <a href="#pricing">{copy.nav.pricing}</a>
                        <a href="#faq">{copy.nav.faq}</a>
                    </nav>
                    {downloadButton("header")}
                </div>
            </header>

            <section className="lp-hero" id="top">
                <div className="lp-wrap lp-hero-grid">
                    <div className="lp-hero-copy">
                        <p className="lp-eyebrow">{copy.hero.eyebrow}</p>
                        <h1 className="lp-h1">
                            {copy.hero.title}{" "}
                            <span className="lp-moss">
                                {copy.hero.titleAccent}
                            </span>
                        </h1>
                        <p className="lp-lede">{copy.hero.lede}</p>
                        <div className="lp-cta">
                            {downloadButton("hero")}
                            <a className="lp-ghost" href="#how">
                                {copy.hero.tryIt}
                                <Icon name="down" size={18} weight={2.2} />
                            </a>
                        </div>
                        <p className="lp-meta">
                            {(download.isStaging
                                ? copy.hero.betaMeta
                                : copy.hero.meta
                            ).map((item) => (
                                <span key={item}>{item}</span>
                            ))}
                        </p>
                        <p className="lp-hero-stat">
                            <b>
                                <span aria-hidden="true">
                                    <TotalStepsCount
                                        totalSteps={totalSteps}
                                        language={language}
                                    />
                                </span>
                                <span className="lp-sr">
                                    {formatSteps(totalSteps, language)}
                                </span>
                            </b>
                            <span>{copy.totalSteps.caption}</span>
                        </p>
                    </div>
                    <div className="lp-hero-phone">
                        <LandingPhone language={language} />
                        <p className="lp-hint">
                            <Icon name="sparkle" size={14} />
                            {copy.hero.hint}
                        </p>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="what">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.what.eyebrow}</p>
                    <div className="lp-body">
                        <div className="lp-what">
                            <p className="lp-statement">
                                {statement[0]}
                                <span className="lp-chip">
                                    <img
                                        src="/landing/companion-fox-avatar.webp"
                                        alt=""
                                        width={24}
                                        height={24}
                                    />
                                    {statement[1]}
                                </span>
                                {statement[2]}
                                <span className="lp-chip">
                                    <img
                                        src="/landing/companion-badger-avatar.webp"
                                        alt=""
                                        width={24}
                                        height={24}
                                    />
                                    {statement[3]}
                                </span>
                                {statement[4]}
                                <span className="lp-chip lp-chip-icon">
                                    <Icon name="heart" size={18} weight={2.2} />
                                    {statement[5]}
                                </span>
                                {statement[6]}
                            </p>
                            <div className="lp-facts">
                                {copy.what.facts.map((fact, index) => (
                                    <span key={fact}>
                                        <Icon
                                            name={factIcons[index]}
                                            size={18}
                                        />
                                        {fact}
                                    </span>
                                ))}
                            </div>
                        </div>
                        <div className="lp-frags">
                            <figure className="lp-card lp-frag">
                                <div className="lp-frag-ui">
                                    {copy.fights.map((fight) => (
                                        <FightRow
                                            key={fight.name}
                                            fight={fight}
                                            language={language}
                                        />
                                    ))}
                                </div>
                                <figcaption>
                                    <b>{copy.what.frags[0][0]}</b>
                                    <span>{copy.what.frags[0][1]}</span>
                                </figcaption>
                            </figure>
                            <figure className="lp-card lp-frag">
                                <div className="lp-frag-ui">
                                    {copy.standings.map((person, index) => (
                                        <div
                                            key={person.name}
                                            className={
                                                index === 0
                                                    ? "lp-standing lp-you"
                                                    : "lp-standing"
                                            }
                                        >
                                            <span>{index + 1}</span>
                                            <img
                                                className="lp-av"
                                                src={`/landing/companion-${person.animal}-avatar.webp`}
                                                alt=""
                                                width={36}
                                                height={36}
                                            />
                                            <div>
                                                <b>{person.name}</b>
                                                <small>{person.seen}</small>
                                            </div>
                                            <strong>{person.total}</strong>
                                        </div>
                                    ))}
                                </div>
                                <figcaption>
                                    <b>{copy.what.frags[1][0]}</b>
                                    <span>{copy.what.frags[1][1]}</span>
                                </figcaption>
                            </figure>
                            <figure className="lp-card lp-frag">
                                <div className="lp-frag-ui">
                                    <PostCard
                                        post={copy.posts[0]}
                                        language={language}
                                    />
                                </div>
                                <figcaption>
                                    <b>{copy.what.frags[2][0]}</b>
                                    <span>{copy.what.frags[2][1]}</span>
                                </figcaption>
                            </figure>
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="goal">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.goal.eyebrow}</p>
                    <div className="lp-body">
                        <div className="lp-goal">
                            <ol className="lp-lines">
                                {copy.goal.lines.map((line) => (
                                    <li key={line}>{line}</li>
                                ))}
                                <li className="lp-win">{copy.goal.win}</li>
                            </ol>
                            <div>
                                <div className="lp-gaps">
                                    {copy.goal.gaps.map(
                                        ([fight, gap, label, note], index) => (
                                            <div
                                                key={fight}
                                                className={
                                                    index === 0
                                                        ? "lp-gap"
                                                        : "lp-gap lp-behind"
                                                }
                                            >
                                                <span className="lp-tag">
                                                    {fight}
                                                </span>
                                                <b>{gap}</b>
                                                <small>{label}</small>
                                                <p>{note}</p>
                                            </div>
                                        ),
                                    )}
                                </div>
                                <div className="lp-card lp-next">
                                    <div className="lp-next-top">
                                        <span>
                                            {copy.goal.nextPose}{" "}
                                            <b>{copy.goal.nextPoseName}</b>
                                        </span>
                                        <b>{copy.goal.toGo}</b>
                                    </div>
                                    <div className="lp-bar">
                                        <i />
                                    </div>
                                    <p>{copy.goal.poseNote}</p>
                                </div>
                                <p className="lp-text lp-note">
                                    {copy.goal.note}
                                </p>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="how">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.how.eyebrow}</p>
                    <div className="lp-body">
                        <div className="lp-how">
                            <div>
                                <h2 className="lp-h2">
                                    {copy.how.title}{" "}
                                    <span className="lp-moss">
                                        {copy.how.titleAccent}
                                    </span>{" "}
                                    {copy.how.titleEnd}
                                </h2>
                                <ol className="lp-steps">
                                    {copy.how.steps.map(
                                        ([title, text], index) => (
                                            <li key={title}>
                                                <b>{index + 1}</b>
                                                <div>
                                                    <h3 className="lp-h3">
                                                        {title}
                                                    </h3>
                                                    <p className="lp-text">
                                                        {text}
                                                    </p>
                                                </div>
                                            </li>
                                        ),
                                    )}
                                </ol>
                            </div>
                            <div className="lp-how-phone">
                                <FightComposerDemo language={language} />
                                <p className="lp-hint">
                                    <Icon name="sparkle" size={14} />
                                    {copy.how.tryIt}
                                </p>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="companions">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.companions.eyebrow}</p>
                    <div className="lp-body">
                        <h2 className="lp-h2">
                            {copy.companions.title}{" "}
                            <span className="lp-moss">
                                {copy.companions.titleAccent}
                            </span>
                        </h2>
                        <p className="lp-lede lp-sec-lede">
                            {copy.companions.lede}
                        </p>
                        <CompanionPicker language={language} />
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="options">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.options.eyebrow}</p>
                    <div className="lp-body">
                        <h2 className="lp-h2">
                            {copy.options.title}{" "}
                            <span className="lp-moss">
                                {copy.options.titleAccent}
                            </span>
                        </h2>
                        <div className="lp-card lp-spec">
                            {copy.options.items.map(([title, text], index) => (
                                <div key={title} className="lp-spec-row">
                                    <i>
                                        <Icon
                                            name={optionIcons[index]}
                                            size={20}
                                        />
                                    </i>
                                    <div>
                                        <b>{title}</b>
                                        <p>{text}</p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="pricing">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.pricing.eyebrow}</p>
                    <div className="lp-body">
                        <div className="lp-price">
                            <div className="lp-free">
                                <span className="lp-tag">
                                    {copy.pricing.tag}
                                </span>
                                <div className="lp-free-num">
                                    {copy.pricing.free}
                                </div>
                                <p>{copy.pricing.text}</p>
                                <ul className="lp-free-list">
                                    {copy.pricing.included.map((item) => (
                                        <li key={item}>
                                            <Icon
                                                name="check"
                                                size={16}
                                                weight={2.6}
                                            />
                                            {item}
                                        </li>
                                    ))}
                                </ul>
                                {downloadButton("hero")}
                            </div>
                            <div className="lp-card lp-later">
                                <p className="lp-later-title">
                                    {copy.pricing.later}
                                </p>
                                {copy.pricing.extras.map(
                                    ([name, price, text]) => (
                                        <div
                                            key={name}
                                            className="lp-later-row"
                                        >
                                            <div>
                                                <b>{name}</b>
                                                <small>{text}</small>
                                            </div>
                                            <strong>{price}</strong>
                                        </div>
                                    ),
                                )}
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-sec" id="faq">
                <div className="lp-wrap">
                    <p className="lp-eyebrow">{copy.faq.eyebrow}</p>
                    <div className="lp-body">
                        <div className="lp-faq">
                            <div>
                                <h2 className="lp-h2">{copy.faq.title}</h2>
                                <p className="lp-text">{copy.faq.note}</p>
                            </div>
                            <FaqSearch language={language} />
                        </div>
                    </div>
                </div>
            </section>

            <section className="lp-end">
                <div className="lp-wrap">
                    <div className="lp-card lp-end-card">
                        <div className="lp-end-art">
                            <img
                                src="/landing/tennis-night.webp"
                                alt={copy.end.art}
                                width={1448}
                                height={1086}
                                loading="lazy"
                            />
                        </div>
                        <div className="lp-end-copy">
                            <h2 className="lp-h2">{copy.end.title}</h2>
                            <p className="lp-lede">{copy.end.text}</p>
                            {downloadButton("hero")}
                        </div>
                    </div>
                </div>
            </section>

            <footer className="lp-footer">
                <div className="lp-wrap">
                    <a
                        className="lp-brand"
                        href="#top"
                        aria-label={copy.homeLabel}
                    >
                        <img
                            src="/landing/app-icon.webp"
                            alt=""
                            width={34}
                            height={34}
                        />
                        <span>FitFight</span>
                    </a>
                    <p>{copy.footer.tagline}</p>
                    <nav>
                        <Link href={copy.footer.privacy[1]}>
                            {copy.footer.privacy[0]}
                        </Link>
                        <Link href={copy.footer.support[1]}>
                            {copy.footer.support[0]}
                        </Link>
                        <a
                            href={copy.footer.otherLanguage[1]}
                            hrefLang={copy.footer.otherLanguage[2]}
                            lang={copy.footer.otherLanguage[2]}
                        >
                            {copy.footer.otherLanguage[0]}
                        </a>
                    </nav>
                    <small>© 2026 FitFight</small>
                </div>
            </footer>
        </main>
    );
}
