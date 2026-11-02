# App Store metadata

English (U.S.) and French (France) App Store copy. Keep the existing approved app name, contact details, territories, and seller settings unless Marc requests a change.

**1.2.0, prepared 16 Oct 2026:** Marc asked for the 1.2.0 listing to match the fitfight.app redesign of 15 Oct. The promotional text, description, What's new and screenshots below use the website's copy and sample people. 1.1.3 (226) was approved and is live. On 18 Oct 2026 Marc asked to submit 1.2.0 right away; What's new was extended with the work merged from 16 to 18 Oct, and `scripts/app-store-release-audit.rb draft` saves this copy and the screenshots. Keywords and the fields in App information are unchanged. On 19 Oct 2026 Marc named the version 1.2.1: the same App Store Connect version was pulled from review and renamed, so this listing, What's new and the screenshots carried over unchanged.

## App information

| Field              | Value                           |
| ------------------ | ------------------------------- |
| App Store name     | `FitFight: Step Challenges`     |
| On-device name     | `FitFight`                      |
| Subtitle           | `Compete on steps with friends` |
| Primary category   | Health & Fitness                |
| Secondary category | Sports                          |
| Bundle ID          | `com.fitfight.mvp`              |
| SKU                | `fitfight`                      |
| Price              | Free                            |
| In-app purchases   | Special companion `com.fitfight.mvp.special` (EUR 0.99), Custom character `com.fitfight.mvp.custom_character` (EUR 2.99), both consumable |
| Advertising        | None                            |
| Privacy Policy URL | `https://fitfight.app/privacy`  |
| Support URL        | `https://fitfight.app/support`  |
| Marketing URL      | `https://fitfight.app`          |
| Copyright          | `2026 Marc Lamy`                |
| Release method     | Automatically release after approval |

## Promotional text

> Join or start a step challenge with friends, let Apple Health keep score, and find out who really walks the most. Free, with no ads or tracking.

## Description

> STEP CHALLENGES WITH FRIENDS
>
> Let friendly competition move you.
>
> FitFight is a step challenge between you and your friends. Decide on challenge length, agree on what the winner gets or the loser does, then get some steps.
>
> HOW IT WORKS
>
> Three steps to start. One winner to finish.
>
> 01
> Start or join a fight
> Pick how long it lasts, type what the loser has to do or what the champion receives, and share the link with others.
>
> 02
> Move to win
> Apple Health keeps the score while you live your day. The standings update as you walk.
>
> 03
> Claim the win
> When time is up, the highest total wins. The loser does what you agreed.
>
> EVERY FIGHT AT A GLANCE
>
> Ahead in green, behind in orange.
> Live standings: Apple Health totals, updated as you walk.
> A Feed for every fight: photos, posts and very serious trash talk.
>
> YOUR COMPANION
>
> Your companion stands in for you in fights, standings and the Feed. It changes pose as your steps add up during the day. Change it any time, unlock a Special, or describe any animal and get your own.
>
> Free, with no ads. Specials and custom companions are optional in-app purchases.

## Keywords

`step challenge,walking,fitness,friends,competition,pedometer,health`

## What is new in 1.3.0

> Dashboard: it opens on your fights, with your win rate in a ring, your place in your last fights and your winning run. Tap a place to see how that fight ended.
> Friends head to head: each friend's score and who leads. Sort A to Z, by most fights or by how long you have been friends.
> Charts: slide across any chart to read its number. Steps marks the days you were in a fight. Tap Weeks and months, or a sport, for bars by day, week and month.
> Inside a fight, Bars shows today at the top.
> Profile shows your companion in the same pose as Fights, from today's steps.
> Fight pictures show your own companion in its running kit.
> Your own companion draws faster, and Create another works at every step.
> New post: Choose starts with nothing ticked, and fights that are over leave the list.
> Fights have no size limit: invite as many people as you like.

## Screenshot set

Six 1320 x 2868 JPEGs per language for the 6.9-inch iPhone set; App Store Connect scales them down for smaller iPhones. The Screenshots workflow captures them from the running app on an iPhone 17 Pro Max simulator in Companion preview, which uses the website's sample people and fights: Alex (you, Tiger), Leo (Silverback), Nina (Capybara), Sam (Hedgehog) and Theo (Panda), in Walk Wars, Eat it and Step it Up, with 8,432 steps today. The 1.2.0 set is in [2026-10-16](2026-10-16/index.html), from the `app-store-screenshots` and `app-store-screenshots-fr` artifacts.

1. Fights with Walk Wars (+860), Step it Up (+2,840) and Eat it (-1,260).
2. Eat it, a live 1v1 against Theo with totals and standings.
3. New with the Tiger: Create, Join or Post, and two suggested fights.
4. An invitation from Sam with Accept and Decline.
5. Profile with Alex, the Tiger and statistics.
6. Feed with the website's three posts from Leo, Nina and Sam.

The Profile capture shows the version line of the simulator build (`1.2.0 · build 1 · prod`). Do not use real names or real Health data in marketing assets.

## French (France) localization

Keep English (U.S.) as the primary App Store language and add French (France) as a localization.

| Field              | Value                             |
| ------------------ | --------------------------------- |
| App Store name     | `FitFight : Défis de pas`         |
| Subtitle           | `Défiez vos amis à pied`          |
| Privacy Policy URL | `https://fitfight.app/fr/privacy` |
| Support URL        | `https://fitfight.app/fr/support` |
| Marketing URL      | `https://fitfight.app`            |

### Promotional text

> Rejoignez ou lancez un défi de pas entre amis, laissez Santé d’Apple compter les pas et découvrez qui marche vraiment le plus. Gratuit, sans pub ni suivi.

### Description

> DÉFIS DE PAS ENTRE AMIS
>
> Bougez plus grâce aux défis entre amis.
>
> FitFight est un défi de pas entre vous et vos amis. Choisissez la durée du défi, mettez-vous d’accord sur ce que gagne le vainqueur ou sur le gage du perdant, puis cumulez les pas.
>
> COMMENT ÇA MARCHE
>
> Trois étapes pour se lancer. Un seul gagnant à l’arrivée.
>
> 01
> Lancez ou rejoignez un défi
> Choisissez sa durée, écrivez le gage du perdant ou ce que remporte le champion, et partagez le lien avec les autres.
>
> 02
> Bougez pour gagner
> Santé d’Apple compte les pas pendant que vous vivez votre journée. Le classement se met à jour à chaque pas.
>
> 03
> Décrochez la victoire
> À la fin, le total le plus élevé gagne. Le perdant fait le gage convenu.
>
> TOUS VOS DÉFIS D’UN COUP D’ŒIL
>
> En avance en vert, en retard en orange.
> Classement en direct : les totaux de Santé d’Apple, mis à jour pendant que vous marchez.
> Un fil pour chaque défi : photos, messages et chambrage très sérieux.
>
> VOTRE COMPAGNON
>
> Votre compagnon vous représente dans les défis, le classement et le fil. Il change de pose à mesure que vos pas s’accumulent dans la journée. Changez-en quand vous voulez, débloquez un Spécial ou décrivez n’importe quel animal pour avoir le vôtre.
>
> Gratuit, sans pub. Les Spéciaux et les compagnons personnalisés sont des achats intégrés facultatifs.

### Keywords

`défi de pas,marche,fitness,amis,compétition,podomètre,santé`

### Nouveautés de la version 1.3.0

> Tableau de bord : il s’ouvre sur vos défis, avec votre taux de victoire dans un anneau, votre place dans vos derniers défis et votre série. Touchez une place pour voir comment ce défi s’est terminé.
> Face-à-face entre amis : le score de chaque ami et qui mène. Triez de A à Z, par nombre de défis ou par ancienneté d’amitié.
> Graphiques : glissez sur n’importe quel graphique pour lire son chiffre. Pas met en avant les jours où vous étiez en défi. Touchez Semaines et mois, ou un sport, pour des barres par jour, semaine et mois.
> Dans un défi, Barres montre aujourd’hui en haut.
> Le Profil montre votre compagnon dans la même pose que dans Défis, selon vos pas du jour.
> Les images de défi montrent votre propre compagnon dans sa tenue de course.
> Votre propre compagnon se dessine plus vite, et En créer un autre marche à chaque étape.
> Nouvelle publication : Choix commence sans rien de coché, et les défis terminés quittent la liste.
> Les défis n’ont plus de limite de taille : invitez autant de personnes que vous voulez.

Use the same six screenshot subjects as English, from the `app-store-screenshots-fr` artifact.
