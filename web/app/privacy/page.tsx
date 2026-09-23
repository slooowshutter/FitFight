import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
    title: "Privacy Policy | FitFight",
    description:
        "How FitFight collects, uses, shares, and deletes account, Fight, and Apple Health data.",
    robots: { index: true, follow: true },
};

export default function PrivacyPage() {
    return (
        <main className="legal-page">
            <header className="legal-header">
                <Link className="brand" href="/" aria-label="FitFight home">
                    <span className="brand-mark">FF</span>
                    <span>FitFight</span>
                </Link>
                <nav className="legal-nav" aria-label="Legal and support">
                    <Link href="/privacy" aria-current="page">
                        Privacy
                    </Link>
                    <Link href="/support">Support</Link>
                </nav>
            </header>

            <article className="legal-content">
                <p className="eyebrow">YOUR DATA, IN PLAIN LANGUAGE</p>
                <h1>Privacy Policy</h1>
                <p className="legal-updated">Effective 23 September 2026</p>
                <p className="legal-intro">
                    FitFight lets named participants compete on who records the
                    most Steps during a private Fight. This policy explains the
                    data used by the FitFight iPhone app and its support
                    website.
                </p>

                <section>
                    <h2>Data we collect</h2>
                    <ul>
                        <li>
                            <strong>Account data:</strong> your Apple or Google
                            account identifier, email address (which may be an
                            Apple private relay address), name and profile image
                            when your sign-in provider supplies them, your
                            FitFight username, chosen
                            companion and optional custom description, and an
                            encrypted server-only Apple credential used to
                            disconnect Sign in with Apple when you delete your
                            account.
                        </li>
                        <li>
                            <strong>Referrals:</strong> a random sharing code
                            and the accounts of the person referring and the
                            person referred, with the time the referral was
                            recorded. We use this to understand who brings
                            friends to FitFight. These relationships stay
                            private and are removed when either account is
                            deleted.
                        </li>
                        <li>
                            <strong>Fight data:</strong> the usernames invited
                            to a Fight, its title, action and duration,
                            membership status, aggregate scores, rank, and
                            timestamps.
                        </li>
                        <li>
                            <strong>Apple Health:</strong> with your permission,
                            FitFight reads Step Count and other movement types
                            (energy, distance, exercise, stand, flights, and
                            workouts). It uploads Apple-merged daily totals
                            across the history you allow FitFight to read,
                            exact Fight-window Steps totals and chart
                            checkpoints, workout summaries, and explicit
                            workout deletion IDs. Only Steps score current
                            Fights. Other activity stays private to your
                            account.
                        </li>
                        <li>
                            <strong>Photos, videos, and posts:</strong> your
                            optional profile photo, Fight posts, photos and
                            videos, comments, and emoji reactions. Posts are
                            shared with members of the Fights you select. The
                            Public label on a post means all selected Fights,
                            not an open internet page. Public Fights have join
                            details visible to other signed-in users before they
                            join.
                        </li>
                        <li>
                            <strong>Bugs and feature requests:</strong> the
                            title, details, votes, and comments, optional
                            photos, videos, and files you post on the in-app
                            board, shown to other signed-in FitFight Users with
                            your username. Reports also include app and device
                            information to help investigate a problem.
                        </li>
                        <li>
                            <strong>Notifications:</strong> when you allow push
                            notifications, an encrypted Apple push device token,
                            language, permission status, and your notification
                            preferences. Apple delivers enabled Fight reminders
                            and post, comment, reaction, and daily-status alerts
                            to your device.
                        </li>
                        <li>
                            <strong>Support and operations:</strong> messages
                            you send to support and limited server logs such as
                            request time, IP address, device or browser
                            information, and error details needed to keep the
                            service secure and working. Private sync diagnostics
                            also record how long Apple Health reads and network
                            requests take, their success or failure, app
                            version, and request sizes. These timing records
                            contain no Steps values or raw Health samples and
                            are not shared with other participants.
                        </li>
                    </ul>
                </section>

                <section>
                    <h2>Apple Health</h2>
                    <p>
                        Apple Health access is read-only. FitFight uploads the
                        supported individual activity samples you allow, with
                        their HealthKit IDs, times, values, units, source name,
                        source app identifier, source version, device model when
                        available, and selected sync identifiers. It also stores
                        merged daily totals, workout summaries, and explicit
                        record deletions. FitFight does not read GPS routes or
                        heart rate. Sync checkpoints stay on your phone. Raw
                        samples are private and never added to Apple&apos;s
                        merged Steps score or shown to Fight participants.
                    </p>
                    <p>
                        Participants in the same private Fight can see each
                        other&apos;s username, aggregate Steps total for the
                        Fight, relevant daily Steps totals shown in the Fight
                        chart, rank, Fight title, Fight action, and duration.
                        They never receive another participant&apos;s raw Apple
                        Health samples. Daily Steps beyond the Fight are shared
                        only through the separate choices described below.
                    </p>
                </section>

                <section id="profiles">
                    <h2>Profiles, Friends, and optional sharing</h2>
                    <p>
                        Profiles start Private and Casual. Your name, username,
                        photo and selected companion identify you in the app.
                        Friendships require the other person to accept. We keep
                        requests, accepted friendships, blocks and reports to
                        provide these features and respond to abuse.
                    </p>
                    <p>
                        Competitive shows your Fight record and eligible
                        head-to-head results. Private limits the shared profile
                        to accepted friends and current Fight opponents. Public
                        allows signed-in FitFight users to see what you share.
                        Turning Competitive off hides profile statistics without
                        changing Fight results. A past opponent keeps the shared
                        Fight result, not ongoing access to your private profile.
                        Private Fight titles, actions, posts and other members
                        are not revealed through a public profile.
                    </p>
                    <p>
                        Daily Steps sharing is off by default. In You → Edit
                        profile, you may separately choose friends, friends and current
                        opponents, or all signed-in users for a Public profile,
                        and a period of 7 or 30 days. This uses stored daily Steps,
                        including each available day&apos;s time zone, freshness
                        and completeness. Missing days are not treated as zero.
                        It does not expand Apple Health collection or share other
                        activity types. You can preview the audience and withdraw
                        sharing at any time. Changing to Private disables public
                        daily Steps sharing.
                    </p>
                    <p>
                        Removing a friend or blocking a person removes the
                        corresponding profile access on subsequent requests.
                        Joining a suggested public Fight is optional and does
                        not enable profile or daily-history sharing. Existing
                        participants still see the data shared within that Fight.
                        Copies someone already viewed or captured cannot be recalled.
                    </p>
                </section>

                <section>
                    <h2>Profile measurement and pair artwork</h2>
                    <p>
                        When profile measurement is enabled, FitFight records
                        successful profile opens using the viewer and target
                        account identifiers, entry point, a random event identifier
                        and server time. Self-views, private lock screens and
                        duplicate event submissions are excluded. Repeat visits
                        qualify at most once per 30 minutes in each direction.
                        We also record friendship requests, acceptances and
                        shared Fight participation, attributing them to the most
                        recent profile visit in the preceding seven days.
                    </p>
                    <p>
                        These internal measurements help assess whether profiles
                        lead to connections. Users do not receive named visitor
                        lists or visit counts. Events contain no Health values,
                        photos or companion descriptions. Raw events are deleted
                        after 30 days by a daily cleanup, including for inactive
                        accounts, and when either account is deleted. Exact
                        username lookup attempts expire after one hour and are
                        used to limit abuse. Only aggregate measurement reports
                        are available to the FitFight operator. Anonymous event totals
                        are retained after the identifiable events expire.
                    </p>
                    <p>
                        Pair artwork generation is currently unavailable. No
                        companion inputs are sent to an image-generation provider.
                        Before enabling it, we will identify the provider, explain
                        the inputs and obtain the participants&apos; specific
                        permission. Profile sharing and Apple Health authorization
                        do not grant permission for external image processing.
                    </p>
                </section>

                <section>
                    <h2>How we use data</h2>
                    <p>We use the data above to:</p>
                    <ul>
                        <li>create and secure your account;</li>
                        <li>
                            create, invite participants to, score, and finish
                            private Fights;
                        </li>
                        <li>show standings and shared Fight history;</li>
                        <li>
                            share posts and media with the selected Fight
                            participants;
                        </li>
                        <li>deliver enabled notifications;</li>
                        <li>run the in-app bugs and feature-request board;</li>
                        <li>answer support requests; and</li>
                        <li>detect errors, abuse, and security problems.</li>
                    </ul>
                    <p>
                        FitFight does not sell personal data, show advertising,
                        or use account or Health data for advertising, cross-app
                        tracking, or data brokerage.
                    </p>
                </section>

                <section>
                    <h2>Who processes data</h2>
                    <p>
                        FitFight uses Supabase for authentication, database, and
                        uploaded-file storage, and Vercel to host server APIs
                        and scheduled processing. These providers process data
                        for FitFight under their service and security terms. We
                        do not make private Fight or Health data public.
                    </p>
                    <p>
                        When configured, PostHog receives crash reports linked
                        to your FitFight account identifier. FitFight disables
                        session replay and screen and interaction capture; its
                        crash integration sends crash reports and account
                        identification. It does not intentionally include Health
                        values in those reports.
                    </p>
                    <p>
                        When configured, bugs and feature requests are copied to
                        our Notion backlog with your username, report text, and
                        attachment links. The FitFight administrator can send a
                        report, its comments, device information, and attachment
                        links to Cursor to investigate and prepare a fix.
                    </p>
                    <p>
                        When daily-status generation is configured and enabled
                        for your account, OpenRouter and its model provider
                        receive a limited summary: whether you are ahead,
                        behind, or tied, participant count, days remaining,
                        whether a sync is needed, and language. This request
                        does not include your account identifier, username,
                        Fight title, exact Steps totals, or raw Health samples.
                    </p>
                    <p>
                        We may also disclose information when required by law,
                        to protect users or the service, or as part of a
                        business transfer subject to appropriate safeguards.
                    </p>
                </section>

                <section>
                    <h2>Permissions, revocation, and retention</h2>
                    <p>
                        You choose whether to grant Apple Health access. You can
                        remove FitFight&apos;s access at any time in Apple
                        Health or iOS Settings. Revoking access stops future
                        reads but does not change data already used to score a
                        Fight.
                    </p>
                    <p>
                        You can manage notification categories under You →
                        Settings → Notifications and remove push permission in
                        iOS Settings.
                    </p>
                    <p>
                        We keep account, Fight, posts, media, bugs and
                        feature-request, and uploaded Health data while your
                        account exists. Support emails are kept only as long as
                        needed to answer the request. Limited security and
                        request logs follow Supabase&apos;s and Vercel&apos;s
                        configured retention periods. Deleted data may remain
                        temporarily in routine backups until those backups
                        expire, or longer when required by law.
                    </p>
                    <p>
                        We keep at most the 100 most recent sync timing reports
                        for your account. Reports older than seven days are
                        removed the next time your app sends a diagnostic
                        report. Deleting your account removes its timing
                        history.
                    </p>
                </section>

                <section>
                    <h2>Account deletion</h2>
                    <p>
                        You can permanently delete your account under{" "}
                        <strong>You → Settings → Delete account</strong>. You do
                        not need to contact support. Deletion removes your
                        profile, username, uploaded photos, videos, files, Fight
                        posts and comments, uploaded Apple Health Fight, daily,
                        activity totals, individual samples, and workout summaries, friendships, invitations, Fight memberships, scores,
                        bugs and feature requests you posted, and every Fight
                        you created. It also removes your participation from
                        Fights created by someone else.
                    </p>
                    <p>
                        In-app deletion does not automatically remove report
                        copies already sent to Notion or Cursor, or crash
                        records already sent to PostHog. Contact{" "}
                        <a href="mailto:marc@marclamy.com">marc@marclamy.com</a>{" "}
                        to request a review of those copies and their retention.
                    </p>
                    <p>
                        When FitFight has a revocable Sign in with Apple
                        credential, it asks Apple to revoke that credential as
                        part of deleting the FitFight login and signing you out.
                        If automatic revocation is unavailable, the app tells
                        you how to disconnect FitFight in Apple settings.
                        Deletion does not remove information stored in Apple
                        Health or delete your Apple ID or Google account. For
                        Google sign-in, the app also attempts to revoke its
                        locally saved Google authorization. You can remove
                        FitFight access in your Google Account&apos;s third-party
                        connections settings.
                    </p>
                </section>

                <section>
                    <h2>Your choices</h2>
                    <p>
                        You may ask to access, correct, or delete information
                        associated with your account. Email{" "}
                        <a href="mailto:marc@marclamy.com">marc@marclamy.com</a>{" "}
                        from the address connected to your account so we can
                        verify the request.
                    </p>
                </section>

                <section>
                    <h2>Changes and contact</h2>
                    <p>
                        We may update this policy when FitFight changes. The
                        effective date above will identify the current version.
                        Questions about privacy can be sent to{" "}
                        <a href="mailto:marc@marclamy.com?subject=FitFight%20privacy">
                            marc@marclamy.com
                        </a>
                        .
                    </p>
                </section>
            </article>

            <footer className="legal-footer">
                <span>© 2026 FitFight</span>
                <Link href="/support">Support</Link>
            </footer>
        </main>
    );
}
