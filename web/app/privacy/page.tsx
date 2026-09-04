import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy | FitFight",
  description: "How FitFight collects, uses, shares, and deletes account, Fight, and Apple Health data.",
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
          <Link href="/privacy" aria-current="page">Privacy</Link>
          <Link href="/support">Support</Link>
        </nav>
      </header>

      <article className="legal-content">
        <p className="eyebrow">YOUR DATA, IN PLAIN LANGUAGE</p>
        <h1>Privacy Policy</h1>
        <p className="legal-updated">Effective 4 September 2026</p>
        <p className="legal-intro">
          FitFight lets named participants compete on who records the most Steps during
          a private Fight. This policy explains the data used by the FitFight iPhone app
          and its support website.
        </p>

        <section>
          <h2>Data we collect</h2>
          <ul>
            <li>
              <strong>Account data:</strong> your Sign in with Apple identifier, email
              address (which may be an Apple private relay address), name when Apple
              supplies it, the FitFight username you choose, and an encrypted server-only
              Apple credential used to disconnect Sign in with Apple when you delete your
              account.
            </li>
            <li>
              <strong>Fight data:</strong> the usernames invited to a Fight, its action
              and duration, membership status, aggregate scores, rank, and timestamps.
            </li>
            <li>
              <strong>Apple Health:</strong> with your permission, FitFight reads Step
              Count to score private Fights, and also stores daily Apple statistics for
              distance, flights climbed, active and basal energy, exercise time, stand
              time, resting heart rate, walking heart-rate average, and body mass, plus
              workout, sleep, and mindful-session summaries. Fight opponents only see Steps
              totals for Fights you share with them.
            </li>
            <li>
              <strong>Bugs and feature requests:</strong> the title, details, votes, and
              comments you post on the in-app board, shown to other signed-in FitFight
              Users with your username.
            </li>
            <li>
              <strong>Support and operations:</strong> messages you send to support and
              limited server logs such as request time, IP address, device or browser
              information, and error details needed to keep the service secure and working.
            </li>
          </ul>
        </section>

        <section>
          <h2>Apple Health</h2>
          <p>
            Apple Health access is read-only. FitFight does not write to Apple Health.
            Steps fights use Apple&apos;s merged Step Count for each exact Fight window
            plus the relevant merged daily totals used by Fight charts. The app does not
            send raw step samples, GPS routes, continuous heart-rate streams, ECG, or
            device and source metadata.
          </p>
          <p>
            With the same Health permission, FitFight also stores the extra types listed
            above as private collection data so we can design later challenge types. That
            collection is not shared with Fight opponents and does not change the Steps
            score of a Fight.
          </p>
          <p>
            Participants in the same private Fight can see each other&apos;s username,
            aggregate Steps total for the Fight, relevant daily Steps totals shown in the
            Fight chart, rank, Fight action, and duration. They never receive another
            participant&apos;s extra Health collection or raw Apple Health samples.
          </p>
        </section>

        <section>
          <h2>How we use data</h2>
          <p>We use the data above to:</p>
          <ul>
            <li>create and secure your account;</li>
            <li>create, invite participants to, score, and finish private Fights;</li>
            <li>show standings and shared Fight history;</li>
            <li>run the in-app bugs and feature-request board;</li>
            <li>answer support requests; and</li>
            <li>detect errors, abuse, and security problems.</li>
          </ul>
          <p>
            FitFight does not sell personal data, show advertising, or use account or
            Health data for advertising, cross-app tracking, or data brokerage.
          </p>
        </section>

        <section>
          <h2>Who processes data</h2>
          <p>
            FitFight uses Supabase for authentication and database services, and Vercel
            to host server APIs and scheduled processing. These providers process data
            for FitFight under their service and security terms. We do not make private
            Fight or Health data public.
          </p>
          <p>
            We may also disclose information when required by law, to protect users or
            the service, or as part of a business transfer subject to appropriate safeguards.
          </p>
        </section>

        <section>
          <h2>Permissions, revocation, and retention</h2>
          <p>
            You choose whether to grant Apple Health access. You can remove FitFight&apos;s
            access at any time in Apple Health or iOS Settings. Revoking access stops
            future reads but does not change data already used to score a Fight.
          </p>
          <p>
            We keep account, Fight, bugs and feature-request, uploaded Steps, and private
            Apple Health collection data while your account exists.
            Support emails are kept only as long as needed to answer the request. Limited
            security and request logs follow Supabase&apos;s and Vercel&apos;s configured retention
            periods. Deleted data may remain temporarily in routine backups until those
            backups expire, or longer when required by law.
          </p>
        </section>

        <section>
          <h2>Account deletion</h2>
          <p>
            You can permanently delete your account under <strong>You → Settings → Delete
            account</strong>. You do not need to contact support. Deletion removes your
            profile and username, uploaded Apple Health Fight and daily totals, private
            Health collection, legacy friendships, invitations, Fight memberships, scores,
            bugs and feature requests you posted, and every Fight you created. It also
            removes your participation from Fights created by someone else.
          </p>
          <p>
            When FitFight has a revocable Sign in with Apple credential, it asks Apple to
            revoke that credential as part of deleting the FitFight login and signing you out.
            If automatic revocation is unavailable, the app tells you how to disconnect
            FitFight in Apple settings. Deletion does not remove information stored in
            Apple Health or delete your Apple ID.
          </p>
        </section>

        <section>
          <h2>Your choices</h2>
          <p>
            You may ask to access, correct, or delete information associated with your
            account. Email <a href="mailto:marc@marclamy.com">marc@marclamy.com</a> from
            the address connected to your account so we can verify the request.
          </p>
        </section>

        <section>
          <h2>Changes and contact</h2>
          <p>
            We may update this policy when FitFight changes. The effective date above will
            identify the current version. Questions about privacy can be sent to{" "}
            <a href="mailto:marc@marclamy.com?subject=FitFight%20privacy">
              marc@marclamy.com
            </a>.
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
