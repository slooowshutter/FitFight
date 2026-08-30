import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Support | FitFight",
  description: "Get help with FitFight accounts, Apple Health Steps, Fight invitations, synchronization, and deletion.",
  robots: { index: true, follow: true },
};

export default function SupportPage() {
  return (
    <main className="legal-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
        <nav className="legal-nav" aria-label="Legal and support">
          <Link href="/privacy">Privacy</Link>
          <Link href="/support" aria-current="page">Support</Link>
        </nav>
      </header>

      <article className="legal-content">
        <p className="eyebrow">FITFIGHT SUPPORT</p>
        <h1>How can we help?</h1>
        <p className="legal-intro">
          Email us with your FitFight username, the app version shown at the top of the
          screen, and a short description of what happened.
        </p>
        <a
          className="primary-action legal-email"
          href="mailto:marc@marclamy.com?subject=FitFight%20support"
        >
          Email marc@marclamy.com
        </a>
        <p className="support-safety">
          Never send your Apple ID password, verification code, or raw Apple Health data.
        </p>

        <section>
          <h2>Apple Health Steps</h2>
          <p>
            In FitFight, open <strong>You → Apple Health</strong> to grant read-only Step
            Count access or retry a sync. FitFight reads aggregate Steps for your active
            Fight windows; background updates depend on iOS and may not be immediate.
          </p>
          <p>
            To revoke access, remove FitFight in Apple Health or iOS Settings. Your score
            may remain incomplete after access is removed.
          </p>
        </section>

        <section>
          <h2>Inviting someone</h2>
          <p>
            Enter their exact FitFight username when creating a Fight. They must first
            sign in with Apple and choose a username. The invitation then appears in
            their Fights list for acceptance.
          </p>
        </section>

        <section>
          <h2>Scores and Fight timing</h2>
          <p>
            FitFight compares Apple Health&apos;s merged Step Count over the same exact
            Fight window for every participant. Open the app to refresh current Steps.
            Steps that occur after the Fight&apos;s end time do not count toward its result.
          </p>
        </section>

        <section>
          <h2>Delete your account</h2>
          <p>
            Open <strong>You → Settings → Delete account</strong> and confirm. If deletion
            fails, email support from the address linked to your account. Shared Fight
            history may retain a deleted-participant placeholder and historical result for
            the other participants.
          </p>
        </section>

        <section>
          <h2>Privacy</h2>
          <p>
            Read the <Link href="/privacy">FitFight Privacy Policy</Link> for details about
            account data, private Fights, Apple Health Steps, service providers, and deletion.
          </p>
        </section>
      </article>

      <footer className="legal-footer">
        <span>© 2026 FitFight</span>
        <Link href="/privacy">Privacy Policy</Link>
      </footer>
    </main>
  );
}
