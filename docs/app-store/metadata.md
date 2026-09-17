# App Store metadata

English (U.S.) and French (France) App Store copy. Keep the existing approved app name, contact details, territories, and seller settings unless Marc requests a change.

Description refresh saved 17 Sep 2026 from Marc's supplied copy, with a French translation. Marc authorized creating the 1.1.2 App Store draft, submitting the update, and automatic publication after approval for every future release. Both descriptions and the required localized release notes below are saved in that draft. Apple blocks review submission because no 1.1.2 build is available. The public version remains 1.1.1 (202); these descriptions are not live. The branch prepares the 1.1.2 native and CI versions and automatic-release defaults. [Cloud configuration](https://github.com/slooowshutter/FitFight/actions/runs/35168925860) confirmed the live 1.1.2 draft has `releaseType: AFTER_APPROVAL` and no selected build. Other fields below remain the 1.1.1 reference metadata; promotional text is blank in the new draft.

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
| In-app purchases   | None                            |
| Advertising        | None                            |
| Privacy Policy URL | `https://fitfight.app/privacy`  |
| Support URL        | `https://fitfight.app/support`  |
| Marketing URL      | `https://fitfight.app`          |
| Copyright          | `2026 Marc Lamy`                |
| Release method     | Automatically release after approval |

## Promotional text

> Challenge friends to private Steps fights, compare Apple Health totals, and see who finishes on top. Free, with no ads, purchases, or tracking.

## Description

> YOUR STEP COMPETITION SCOREKEEPER
>
> Let friendly competition move you.
>
> Connect Apple Health, start a private group challenge, and see who records the most steps.
>
> HOW IT WORKS
>
> Three steps to start. One winner to finish.
>
> 01
> Add your friends
> Search by username and add to any fight.
>
> 02
> Move to win
> Apple Health securely keeps the score while you live your day.
>
> 03
> Claim the win
> Watch the standings, close the gap, and finish on top.

## Keywords

`step challenge,walking,fitness,friends,competition,pedometer,health`

## What is new in 1.1.2

> A refreshed App Store description explaining how to start a private step challenge and follow the standings.

## Screenshot set

Use screenshots generated from the final release commit, showing `prod` in the version line and fictional usernames and Steps. The refresh package contains these six screens as 1320 × 2868 JPEGs for the highest-resolution 6.9-inch iPhone set; App Store Connect scales that set down for smaller iPhone displays:

1. Fights list with live private Steps Fights.
2. Accepted Fight with totals, daily progress, and standings.
3. New Fight setup with Steps, duration, username, and action fields.
4. Incoming invitation with Accept and Decline.
5. You with the companion, Apple Health, and Settings.
6. Feed with fictional posts and photos.

The [interactive gallery](2026-09-15/index.html) contains both languages and the exact icon PNG. Refresh the visible version/build labels from the final production candidate before submission.

Do not submit old design-source screenshots: they contain removed Requests, money, unsupported metrics, and mock data. Do not use real names or real Health data in marketing assets.

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

> Lancez des défis de pas privés à vos amis, comparez vos totaux Santé d’Apple et découvrez qui termine en tête. Gratuit, sans publicité, achat ni suivi.

### Description

> LE COMPTEUR DE VOS DÉFIS DE PAS
>
> Bougez plus grâce aux défis entre amis.
>
> Connectez Santé d’Apple, lancez un défi privé en groupe et découvrez qui fait le plus de pas.
>
> COMMENT ÇA MARCHE
>
> Trois étapes pour se lancer. Un seul gagnant à l’arrivée.
>
> 01
> Ajoutez vos amis
> Recherchez-les par nom d’utilisateur et invitez-les à un défi.
>
> 02
> Bougez pour gagner
> Santé d’Apple comptabilise vos pas en toute sécurité pendant que vous vivez votre journée.
>
> 03
> Décrochez la victoire
> Suivez le classement, réduisez l’écart et terminez en tête.

### Keywords

`défi de pas,marche,fitness,amis,compétition,podomètre,santé`

### Nouveautés de la version 1.1.2

> Une description App Store actualisée pour découvrir comment lancer un défi de pas privé et suivre le classement.

Use the same six screenshot subjects as English, rendered with the app language set to French and fictional usernames and Health data.
