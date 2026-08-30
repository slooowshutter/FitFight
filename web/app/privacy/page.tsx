import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy | FitFight",
  description: "How FitFight collects, uses, shares, and deletes account, Fight, and Apple Health Steps data.",
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
        <p className="legal-updated">Effective 30 August 2026</p>
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
              supplies it, and the FitFight username you choose.
            </li>
            <li>
              <strong>Fight data:</strong> the usernames invited to a Fight, its action
              and duration, membership status, aggregate scores, rank, and timestamps.
            </li>
            <li>
              <strong>Apple Health Steps:</strong> with your permission, FitFight reads
              Step Count and sends the merged total for each exact Fight window plus the
              relevant merged daily totals used by Fight charts.
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
            Apple Health access is read-only and limited to Step Count. FitFight does not
            write to Apple Health. The current app does not send raw Health samples,
            individual workouts, routes, heart rate, or device and source metadata to
            FitFight servers.
          </p>
          <p>
            Participants in the same private Fight can see each other&apos;s username,
            aggregate Steps total, rank, Fight action, and duration. They never receive
            another participant&apos;s raw Apple Health samples or unrelated Health history.
          </p>
        </section>

        <section>
          <h2>How we use data</h2>
          <p>We use the data above to:</p>
          <ul>
            <li>create and secure your account;</li>
            <li>create, invite participants to, score, and finish private Fights;</li>
            <li>show standings and shared Fight history;</li>
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
            We retain account and Fight information while it is needed to operate the
            service and preserve shared Fight results. Operational logs are retained only
            as reasonably needed for security and reliability.
          </p>
        </section>

        <section>
          <h2>Account deletion</h2>
          <p>
            You can request deletion in the app under <strong>You → Settings → Delete
            account</strong>. You can also contact us if the in-app action fails. Deletion
            removes private Health data and login access associated with the account where
            possible.
          </p>
          <p>
            Because a Fight is shared with other participants, its action, dates, aggregate
            result, and a non-identifying deleted-participant placeholder may remain in
            their Fight history. Limited identifiers may also be retained where necessary
            to preserve that shared history, prevent abuse, or meet legal obligations.
            Deleting FitFight does not delete information stored in Apple Health.
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
