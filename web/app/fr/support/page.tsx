import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Assistance | FitFight",
  description:
    "Obtenez de l’aide pour votre compte FitFight, les pas de Santé d’Apple, les invitations, la synchronisation et la suppression.",
  robots: { index: true, follow: true },
};

export default function SupportPage() {
  return (
    <main className="legal-page" lang="fr">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="Accueil FitFight">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
        <nav className="legal-nav" aria-label="Confidentialité et assistance">
          <Link href="/fr/privacy">Confidentialité</Link>
          <Link href="/fr/support" aria-current="page">Assistance</Link>
        </nav>
      </header>

      <article className="legal-content">
        <p className="eyebrow">ASSISTANCE FITFIGHT</p>
        <h1>Comment pouvons-nous vous aider ?</h1>
        <p className="legal-intro">
          Écrivez-nous en indiquant votre nom d’utilisateur FitFight, la version affichée en
          haut de l’écran et une courte description du problème.
        </p>
        <a
          className="primary-action legal-email"
          href="mailto:marc@marclamy.com?subject=Assistance%20FitFight"
        >
          Écrire à marc@marclamy.com
        </a>
        <p className="support-safety">
          N’envoyez jamais votre mot de passe Apple, votre code de vérification ni vos données
          Santé d’Apple brutes.
        </p>

        <section>
          <h2>Pas de Santé d’Apple</h2>
          <p>
            Dans FitFight, ouvrez <strong>Vous → Santé d’Apple</strong> pour autoriser la
            lecture du nombre de pas ou relancer une synchronisation. FitFight lit les pas
            agrégés pendant les périodes de défi actives ainsi que les totaux quotidiens
            utiles aux graphiques. Les mises à jour en arrière-plan dépendent d’iOS et peuvent
            ne pas être immédiates.
          </p>
          <p>
            Pour révoquer l’accès, retirez FitFight dans Santé d’Apple ou les Réglages iOS.
            Votre score peut rester incomplet après la révocation.
          </p>
        </section>

        <section>
          <h2>Inviter une personne</h2>
          <p>
            Saisissez son nom d’utilisateur FitFight exact lors de la création d’un défi.
            Cette personne doit d’abord se connecter avec Apple et choisir un nom d’utilisateur.
            L’invitation apparaît ensuite dans sa liste Défis.
          </p>
        </section>

        <section>
          <h2>Scores et durée du défi</h2>
          <p>
            FitFight compare le nombre de pas fusionné par Santé d’Apple sur la même période
            exacte pour chaque participant. Ouvrez l’app pour actualiser les pas. Les pas
            effectués après l’heure de fin ne comptent pas dans le résultat.
          </p>
        </section>

        <section>
          <h2>Supprimer votre compte</h2>
          <p>
            Ouvrez <strong>Vous → Réglages → Supprimer le compte</strong> et confirmez. Cette
            action supprime définitivement votre profil, les pas envoyés, les invitations et
            participations, vous retire des défis créés par d’autres personnes et supprime
            pour tous les participants les défis que vous avez créés. FitFight demande aussi
            à Apple de révoquer tout identifiant Connexion avec Apple disponible, puis vous
            déconnecte. Cette action est irréversible.
          </p>
          <p>
            Si la révocation Apple automatique était indisponible, suivez le message affiché
            dans l’app pour déconnecter FitFight dans les Réglages de l’iPhone. Si la suppression
            échoue, réessayez puis écrivez à l’assistance depuis l’adresse liée à votre compte.
          </p>
        </section>

        <section>
          <h2>Confidentialité</h2>
          <p>
            Consultez la <Link href="/fr/privacy">politique de confidentialité FitFight</Link>
            pour en savoir plus sur les données du compte, les défis privés, les pas de Santé
            d’Apple, les prestataires et la suppression.
          </p>
        </section>
      </article>

      <footer className="legal-footer">
        <span>© 2026 FitFight</span>
        <Link href="/fr/privacy">Politique de confidentialité</Link>
      </footer>
    </main>
  );
}
