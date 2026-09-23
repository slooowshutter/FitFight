import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
    title: "Politique de confidentialité | FitFight",
    description:
        "Comment FitFight collecte, utilise, partage et supprime les données de compte, de défis et de pas de Santé d’Apple.",
    robots: { index: true, follow: true },
};

export default function PrivacyPage() {
    return (
        <main className="legal-page" lang="fr">
            <header className="legal-header">
                <Link className="brand" href="/" aria-label="Accueil FitFight">
                    <span className="brand-mark">FF</span>
                    <span>FitFight</span>
                </Link>
                <nav
                    className="legal-nav"
                    aria-label="Confidentialité et assistance"
                >
                    <Link href="/fr/privacy" aria-current="page">
                        Confidentialité
                    </Link>
                    <Link href="/fr/support">Assistance</Link>
                </nav>
            </header>

            <article className="legal-content">
                <p className="eyebrow">VOS DONNÉES, EN TOUTE CLARTÉ</p>
                <h1>Politique de confidentialité</h1>
                <p className="legal-updated">En vigueur le 23 septembre 2026</p>
                <p className="legal-intro">
                    FitFight permet à des participants identifiés de comparer le
                    nombre de pas enregistrés pendant un défi privé. Cette
                    politique décrit les données utilisées par l’app FitFight
                    pour iPhone et son site d’assistance.
                </p>

                <section>
                    <h2>Données collectées</h2>
                    <ul>
                        <li>
                            <strong>Données du compte :</strong> votre
                            identifiant Connexion avec Apple, votre adresse
                            e-mail, qui peut être une adresse relais privée
                            Apple, votre nom lorsqu’Apple le fournit, votre nom
                            d’utilisateur FitFight, votre compagnon choisi et sa
                            description personnalisée facultative, ainsi qu’ un
                            identifiant Apple chiffré, réservé au serveur,
                            permettant de déconnecter Connexion avec Apple
                            lorsque vous supprimez votre compte.
                        </li>
                        <li>
                            <strong>Parrainages :</strong> un code de partage
                            aléatoire, les comptes du parrain et de la personne
                            parrainée, ainsi que la date du parrainage. Cela
                            nous permet de savoir qui invite des amis sur
                            FitFight. Ces liens restent privés et sont supprimés
                            lorsque l’un des deux comptes est supprimé.
                        </li>
                        <li>
                            <strong>Données des défis :</strong> les noms
                            d’utilisateur invités, le gage, la durée, l’état de
                            participation, les scores agrégés, le classement et
                            les horodatages.
                        </li>
                        <li>
                            <strong>Santé d’Apple :</strong> avec votre
                            autorisation, FitFight lit les pas et d’autres
                            activités (énergie, distances, exercice, périodes
                            debout, étages montés et entraînements). L’app
                            transmet les totaux quotidiens fusionnés de
                            l’historique auquel vous lui donnez accès, les
                            totaux de pas et points du graphique des défis,
                            les résumés d’entraînement et les identifiants
                            des entraînements supprimés. Seuls les pas
                            comptent pour les défis actuels. Les autres
                            activités restent privées sur votre compte.
                        </li>
                        <li>
                            <strong>Photos, vidéos et publications :</strong>{" "}
                            votre photo de profil facultative, vos publications,
                            photos, vidéos, commentaires et réactions. Les
                            publications sont visibles des membres des défis
                            sélectionnés. Le libellé Public signifie tous les
                            défis sélectionnés, pas une page ouverte sur
                            internet. Les informations permettant de rejoindre
                            un défi public sont visibles des utilisateurs
                            connectés avant leur participation.
                        </li>
                        <li>
                            <strong>Bugs et demandes :</strong> le titre, le
                            détail, les votes et les commentaires, photos,
                            vidéos et fichiers facultatifs que vous publiez dans
                            l’app, visibles des autres utilisateurs connectés
                            avec votre nom d’utilisateur. Les signalements
                            incluent aussi des informations sur l’app et
                            l’appareil.
                        </li>
                        <li>
                            <strong>Notifications :</strong> si vous autorisez
                            les notifications, un jeton d’appareil Apple
                            chiffré, la langue, l’état de l’autorisation et vos
                            préférences. Apple transmet les alertes activées
                            pour les défis, publications, commentaires,
                            réactions et bilans quotidiens.
                        </li>
                        <li>
                            <strong>Assistance et fonctionnement :</strong> les
                            messages envoyés à l’assistance et des journaux
                            serveur limités, comme l’heure de la requête,
                            l’adresse IP, les informations sur l’appareil ou le
                            navigateur et les détails d’erreur nécessaires à la
                            sécurité et au fonctionnement du service. Des
                            diagnostics privés enregistrent aussi la durée des
                            lectures de Santé et des requêtes réseau, leur
                            réussite ou leur échec, la version de l’app et la
                            taille des requêtes. Ces mesures ne contiennent ni
                            nombre de pas ni échantillons Santé bruts et ne sont
                            pas partagées avec les participants.
                        </li>
                    </ul>
                </section>

                <section>
                    <h2>Santé d’Apple</h2>
                    <p>
                        L’accès à Santé d’Apple est en lecture seule. FitFight
                        envoie les échantillons individuels autorisés avec leur
                        identifiant Santé, leurs horaires, valeurs, unités, nom
                        et identifiant de l’app source, version de la source,
                        modèle d’appareil si disponible et certains identifiants
                        de synchronisation. L’app conserve aussi les totaux
                        quotidiens fusionnés, les résumés d’entraînement et les
                        suppressions explicites. FitFight ne lit ni itinéraires
                        GPS ni fréquences cardiaques. Les points de reprise
                        restent sur votre téléphone. Les échantillons bruts
                        restent privés et ne sont jamais ajoutés au score de
                        pas fusionné par Apple ni montrés aux participants.
                    </p>
                    <p>
                        Les participants d’un même défi privé peuvent voir les
                        noms d’utilisateur, le total agrégé de pas du défi, les
                        totaux quotidiens affichés dans le graphique, le
                        classement, le gage et la durée. Ils ne reçoivent jamais
                        les échantillons Santé bruts. Les pas quotidiens hors du
                        Fight ne sont partagés qu’avec les réglages séparés
                        décrits ci-dessous.
                    </p>
                </section>

                <section id="profiles">
                    <h2>Profils, amis et partage facultatif</h2>
                    <p>
                        Les profils sont privés et en mode détente par défaut.
                        Votre nom, pseudo, photo et compagnon vous identifient
                        dans l’app. Une amitié nécessite l’acceptation de l’autre
                        personne. Nous conservons les demandes, amitiés, blocages
                        et signalements pour fournir ces fonctions et traiter les abus.
                    </p>
                    <p>
                        Le mode Compétitif affiche vos résultats et les duels
                        admissibles. Un profil privé les réserve aux amis acceptés
                        et aux adversaires d’un Fight en cours. Un profil public
                        les partage avec les utilisateurs FitFight connectés.
                        Désactiver Compétitif masque ces statistiques sans modifier
                        les résultats. Un ancien adversaire conserve le résultat
                        du Fight commun, sans accès permanent au profil privé.
                        Un profil public ne révèle pas les titres, gages,
                        publications ou autres membres des Fights privés.
                    </p>
                    <p>
                        Le partage des pas quotidiens est désactivé par défaut.
                        Dans Vous → Modifier le profil, vous pouvez choisir
                        séparément les amis, les amis et adversaires actuels, ou tous les
                        utilisateurs connectés avec un profil public, sur 7 ou
                        30 jours. Ce partage utilise les pas déjà enregistrés,
                        leur fuseau horaire lorsqu’il est disponible, leur date
                        de mise à jour et leur complétude. Une journée absente
                        n’est pas un zéro. Il n’étend ni la collecte Santé ni le
                        partage aux autres types d’activité. Vous pouvez vérifier
                        l’aperçu et retirer le partage à tout moment. Passer en
                        privé désactive le partage public des pas quotidiens.
                    </p>
                    <p>
                        Retirer un ami ou bloquer une personne supprime les accès
                        correspondants lors des requêtes suivantes. Rejoindre un
                        Fight public suggéré reste facultatif et n’active pas le
                        partage du profil ou des journées. Les participants voient
                        toujours les données partagées dans ce Fight. Les copies
                        déjà vues ou capturées ne peuvent pas être rappelées.
                    </p>
                </section>

                <section>
                    <h2>Mesure des profils et illustrations de rivalité</h2>
                    <p>
                        Lorsque cette mesure est activée, FitFight enregistre les
                        ouvertures réussies avec les identifiants des deux comptes,
                        le point d’entrée, un identifiant d’événement aléatoire et
                        l’heure du serveur. Les visites de son propre profil, les
                        écrans privés verrouillés et les envois répétés du même
                        événement sont exclus. Une visite répétée est qualifiée
                        au maximum toutes les 30 minutes dans chaque sens. Les
                        demandes d’amitié, acceptations et participations communes
                        sont aussi enregistrées et attribuées à la dernière visite
                        du profil dans les sept jours précédents.
                    </p>
                    <p>
                        Ces mesures internes servent à comprendre les rencontres
                        permises par les profils. Les utilisateurs ne reçoivent
                        ni liste nominative de visiteurs ni compteur de visites.
                        Ces événements ne contiennent ni valeurs Santé, ni photos,
                        ni descriptions de compagnons. Un nettoyage quotidien
                        supprime les événements de plus de 30 jours, même pour
                        les comptes inactifs. La suppression de l’un des comptes
                        efface les événements associés. Les tentatives de recherche
                        de pseudo expirent après une heure et limitent les abus.
                        Seuls des rapports agrégés sont accessibles à l’opérateur.
                    </p>
                    <p>
                        Des totaux anonymes sont conservés après la suppression
                        des événements identifiants.
                    </p>
                    <p>
                        La génération d’illustrations de rivalité est indisponible.
                        Aucun compagnon n’est envoyé à un fournisseur de génération
                        d’images. Avant son activation, nous nommerons le fournisseur,
                        expliquerons les données transmises et demanderons une
                        autorisation spécifique aux deux participants. Le partage
                        du profil et l’autorisation Santé ne permettent pas ce
                        traitement externe.
                    </p>
                </section>

                <section>
                    <h2>Utilisation des données</h2>
                    <p>Nous utilisons ces données pour :</p>
                    <ul>
                        <li>créer et sécuriser votre compte ;</li>
                        <li>
                            créer, gérer, comptabiliser et terminer les défis
                            privés ;
                        </li>
                        <li>
                            afficher les classements et l’historique partagé des
                            défis ;
                        </li>
                        <li>
                            partager les publications et médias avec les
                            participants sélectionnés ;
                        </li>
                        <li>transmettre les notifications activées ;</li>
                        <li>
                            faire fonctionner le tableau de bugs et de demandes
                            dans l’app ;
                        </li>
                        <li>répondre aux demandes d’assistance ;</li>
                        <li>
                            détecter les erreurs, abus et problèmes de sécurité.
                        </li>
                    </ul>
                    <p>
                        FitFight ne vend pas de données personnelles, n’affiche
                        pas de publicité et n’utilise pas les données du compte
                        ou de Santé pour la publicité, le suivi entre apps ou le
                        courtage de données.
                    </p>
                </section>

                <section>
                    <h2>Prestataires traitant les données</h2>
                    <p>
                        FitFight utilise Supabase pour l’authentification, la
                        base de données et les fichiers, et Vercel pour héberger
                        les API serveur et les traitements planifiés. Ces
                        prestataires traitent les données pour FitFight selon
                        leurs conditions de service et de sécurité. Nous ne
                        rendons publiques aucune donnée privée de défi ou de
                        Santé.
                    </p>
                    <p>
                        Lorsque l’intégration est configurée, PostHog reçoit des
                        rapports de plantage liés à votre identifiant de compte
                        FitFight. L’app désactive l’enregistrement des sessions,
                        des écrans et des interactions. Les rapports et
                        l’identification du compte ne contiennent pas
                        intentionnellement de valeurs de Santé.
                    </p>
                    <p>
                        Lorsque l’intégration est configurée, les bugs et
                        demandes sont copiés dans notre backlog Notion avec le
                        nom d’utilisateur, le texte et les liens des pièces
                        jointes. L’administrateur FitFight peut envoyer un
                        signalement, ses commentaires, les informations
                        d’appareil et les liens des pièces jointes à Cursor pour
                        examiner le problème et préparer une correction.
                    </p>
                    <p>
                        Lorsque les bilans quotidiens sont configurés et activés
                        pour votre compte, OpenRouter et son fournisseur de
                        modèle reçoivent un résumé limité : avance, retard ou
                        égalité, nombre de participants, jours restants, besoin
                        de synchroniser et langue. Aucun identifiant de compte,
                        nom d’utilisateur, titre de défi, total exact de pas ou
                        échantillon Santé brut ne figure dans cette requête.
                    </p>
                    <p>
                        Nous pouvons également communiquer des informations
                        lorsque la loi l’exige, pour protéger les utilisateurs
                        ou le service, ou dans le cadre d’un transfert
                        d’activité assorti de garanties appropriées.
                    </p>
                </section>

                <section>
                    <h2>Autorisations, révocation et conservation</h2>
                    <p>
                        Vous choisissez d’autoriser ou non l’accès à Santé
                        d’Apple. Vous pouvez retirer l’accès de FitFight à tout
                        moment dans Santé d’Apple ou les Réglages iOS. La
                        révocation interrompt les lectures futures, mais ne
                        modifie pas les données déjà utilisées pour
                        comptabiliser un défi.
                    </p>
                    <p>
                        Vous pouvez gérer les catégories de notifications sous
                        Vous → Réglages → Notifications, et retirer
                        l’autorisation dans les Réglages iOS.
                    </p>
                    <p>
                        Nous conservons les données du compte, des défis, des
                        publications, des médias, des bugs et demandes, et les
                        données de Santé envoyées tant que votre compte existe.
                        Les e-mails d’assistance sont conservés le temps
                        nécessaire au traitement de la demande. Les journaux
                        limités de sécurité et de requêtes suivent les durées de
                        conservation configurées chez Supabase et Vercel. Des
                        données supprimées peuvent rester temporairement dans
                        les sauvegardes ordinaires jusqu’à leur expiration, ou
                        plus longtemps lorsque la loi l’exige.
                    </p>
                    <p>
                        Nous conservons au maximum les 100 rapports de durée de
                        synchronisation les plus récents de votre compte. Les
                        rapports de plus de sept jours sont supprimés lors du
                        prochain envoi de diagnostics par votre app. La
                        suppression du compte efface cet historique.
                    </p>
                </section>

                <section>
                    <h2>Suppression du compte</h2>
                    <p>
                        Vous pouvez supprimer définitivement votre compte sous{" "}
                        <strong>Vous → Réglages → Supprimer le compte</strong>,
                        sans contacter l’assistance. La suppression efface votre
                        profil et votre nom d’utilisateur, les photos, vidéos et
                        fichiers envoyés, les publications et commentaires, les
                        totaux de pas et d’activité et les résumés
                        d’entraînement, les relations d’amitié, les
                        invitations, participations et scores, les bugs et
                        demandes que vous avez publiés, ainsi que tous les défis
                        que vous avez créés. Elle vous retire également des
                        défis créés par une autre personne.
                    </p>
                    <p>
                        La suppression dans l’app n’efface pas automatiquement
                        les copies déjà envoyées à Notion ou Cursor, ni les
                        rapports de plantage envoyés à PostHog. Contactez{" "}
                        <a href="mailto:marc@marclamy.com">marc@marclamy.com</a>{" "}
                        pour demander un examen de ces copies et de leur
                        conservation.
                    </p>
                    <p>
                        Lorsque FitFight possède un identifiant Connexion avec
                        Apple révocable, l’app demande à Apple de le révoquer
                        lors de la suppression du compte FitFight et vous
                        déconnecte. Si la révocation automatique est
                        indisponible, l’app explique comment déconnecter
                        FitFight dans les réglages Apple. La suppression
                        n’efface aucune donnée stockée dans Santé d’Apple et ne
                        supprime pas votre identifiant Apple.
                    </p>
                </section>

                <section>
                    <h2>Vos choix</h2>
                    <p>
                        Vous pouvez demander l’accès, la correction ou la
                        suppression des informations associées à votre compte.
                        Écrivez à{" "}
                        <a href="mailto:marc@marclamy.com">marc@marclamy.com</a>
                        depuis l’adresse liée à votre compte afin que nous
                        puissions vérifier la demande.
                    </p>
                </section>

                <section>
                    <h2>Modifications et contact</h2>
                    <p>
                        Nous pouvons mettre à jour cette politique lorsque
                        FitFight évolue. La date d’entrée en vigueur ci-dessus
                        identifie la version actuelle. Pour toute question sur
                        la confidentialité, écrivez à{" "}
                        <a href="mailto:marc@marclamy.com?subject=Confidentialit%C3%A9%20FitFight">
                            marc@marclamy.com
                        </a>
                        .
                    </p>
                </section>
            </article>

            <footer className="legal-footer">
                <span>© 2026 FitFight</span>
                <Link href="/fr/support">Assistance</Link>
            </footer>
        </main>
    );
}
