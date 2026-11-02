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

## What is new in 1.2.1

> Friends: a Steps fight with each friend that runs the whole month and starts again on the 1st. Tap Friends at the top of Fights.
> Fight Marc: when you sign up, start a 30-day Steps fight against FitFight's founder.
> Player cards: tap a name to see your record against that person, your steps side by side and your fights together.
> Every fight has its own picture: everyone's companions running together.
> Repeating fights: History shows every round with its podium, an all-time leaderboard and records.
> New post: send it to everyone, or choose your friends and the fights that see it. Feed shows how many new posts are waiting.
> Make your own companion on one page, play Snake while it draws, then give it a name and a line.
> Settings has Connectors for Apple Health, Garmin and WHOOP.
> Usernames show as you type, you can change your fight's code, and FitFight opens on your last fights, even offline.

## Screenshot set

Six 1320 x 2868 JPEGs per language for the 6.9-inch iPhone set; App Store Connect scales them down for smaller iPhones. The Screenshots workflow captures them from the running app on an iPhone 17 Pro Max simulator in Companion preview, which uses the website's sample people and fights: Alex (you, Tiger), Leo (Silverback), Nina (Capybara), Sam (Hedgehog) and Theo (Panda), in Walk Wars, Step it Up, Roommate Rumble and Office Showdown, with 8,432 steps today. The 1.2.0 set is in [2026-10-16](2026-10-16/index.html), from the `app-store-screenshots` and `app-store-screenshots-fr` artifacts. That set still shows Roommate Rumble under its old name, Eat it, and has no Office Showdown.

1. Fights with Walk Wars (+860), Step it Up (+2,840) and Office Showdown (-430), then Roommate Rumble (-1,260) below.
2. Roommate Rumble, a live 1v1 against Theo with totals and standings.
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

### Nouveautés de la version 1.2.1

> Amis : un défi de pas avec chaque ami, sur tout le mois, qui recommence le 1er. Touchez Amis en haut de Défis.
> Affrontez Marc : à l’inscription, lancez un défi de pas de 30 jours contre le fondateur de FitFight.
> Cartes de joueur : touchez un nom pour voir votre bilan face à cette personne, vos pas côte à côte et vos défis en commun.
> Chaque défi a sa propre image : les compagnons de tout le monde qui courent ensemble.
> Défis récurrents : l’Historique montre chaque manche avec son podium, un classement de tous les temps et des records.
> Nouvelle publication : envoyez-la à tout le monde, ou choisissez les amis et les défis qui la voient. Le Fil indique combien de nouvelles publications vous attendent.
> Créez votre compagnon sur une seule page, jouez à Snake pendant qu’il se dessine, puis donnez-lui un nom et une phrase.
> Les Réglages ont des Connexions pour Santé d’Apple, Garmin et WHOOP.
> Les noms d’utilisateur s’affichent pendant la saisie, vous pouvez changer le code de votre défi, et FitFight s’ouvre sur vos derniers défis, même hors ligne.

Use the same six screenshot subjects as English, from the `app-store-screenshots-fr` artifact.
