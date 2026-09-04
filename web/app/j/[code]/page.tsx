import type { Metadata } from "next";
import Link from "next/link";

type JoinPageProps = {
  params: Promise<{ code: string }>;
};

export async function generateMetadata({ params }: JoinPageProps): Promise<Metadata> {
  const { code } = await params;
  return {
    title: `Join ${code.toUpperCase()} | FitFight`,
    description: "Open this fight in FitFight.",
    robots: { index: false, follow: false },
  };
}

export default async function JoinPage({ params }: JoinPageProps) {
  const { code } = await params;
  const display = code.replace(/[\s-]/g, "").toUpperCase();

  return (
    <main className="legal-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
      </header>
      <article className="legal-content">
        <p className="eyebrow">JOIN A FIGHT</p>
        <h1>Open this fight in FitFight</h1>
        <p className="legal-intro">
          Code <strong>{display}</strong>. On iPhone, this link opens FitFight so you can
          join. Scores stay in the app.
        </p>
      </article>
    </main>
  );
}
