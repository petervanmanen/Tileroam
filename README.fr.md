# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · **Français** · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam est une app pour iPhone et iPad qui montre partout où vous êtes allé lors de vos sorties à vélo, courses et marches : chaque tuile de carte, commune et zone de code postal visitée. Elle lit les fichiers `.fit` d’un ou plusieurs dossiers iCloud Drive (par exemple des exports HealthFit, Garmin ou Wahoo) et peut importer votre historique Strava. Elle planifie aussi des parcours à vélo vers des lieux où vous n’êtes pas encore allé.

![Tileroam sur iPhone : tuiles, squadratinhos, communes et planification](docs/screenshots/overview.jpg)

## Fonctionnalités

- **Tuiles** : tuiles de carte au zoom 14 (~1,5 km, comme sur VeloViewer, StatsHunters et [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) et *squadratinhos* au zoom 17 (~190 m, comme sur Squadrats). Les deux sont toujours comptés ; vous choisissez celui que la carte affiche. Avec votre **carré max** et votre **plus grand cluster**.
- **Parcours** : toutes vos activités sur une seule carte, colorées par sport.
- **Communes et codes postaux** aux Pays-Bas, en Belgique et au Luxembourg, avec visités/total par pays.
- **Planification d’itinéraire** : touchez des tuiles, communes ou codes postaux non visités et Tileroam planifie la boucle à vélo la plus courte depuis votre position en passant par tous. Partagez-la en **GPX** ou enregistrez-la dans votre dossier iCloud. Vous pouvez aussi ouvrir un GPX existant pour voir quels nouveaux lieux il permettrait de collecter.
- **Strava** : importez tout votre historique avec le GPS. Les activités sont aussi enregistrées en fichiers `.fit` standard dans le dossier de votre choix.
- **Doublons fusionnés** : une même séance enregistrée par plusieurs appareils ou apps (montre, Zwift, Strava, HealthFit) ne compte qu’une fois.
- **Nombre d’Eddington** pour le vélo et la course, aussi en **widget** sur l’écran d’accueil et l’écran verrouillé.
- **Statistiques** : pays et communes visités, nombres d’Eddington pour le vélo, la marche et la course, et totaux par sport pour cette année et depuis le début.
- Les **sorties en intérieur et virtuelles** (Zwift, Rouvy, MyWhoosh, home trainer) comptent dans les statistiques mais restent hors de la carte, des tuiles, des communes et des codes postaux.
- **Stockage facultatif** : sans dossier choisi, Tileroam enregistre parcours et fichiers Strava dans son propre stockage (app Fichiers › Sur mon iPhone › Tileroam) et lit aussi les fichiers `.fit` de son dossier Import.
- Mise en page **iPad** avec panneau latéral, toutes les orientations et le multitâche.
- Disponible en **anglais, néerlandais, français, espagnol et allemand**.
- La carte s’ouvre sur votre plus grand cluster, là où vous roulez le plus.

## Captures d’écran

| Tuiles (zoom 14) | Squadratinhos (zoom 17) | Parcours | Communes |
|---|---|---|---|
| ![Tuiles](docs/screenshots/tiles.jpg) | ![Squadratinhos](docs/screenshots/squadratinhos.jpg) | ![Parcours](docs/screenshots/routes.jpg) | ![Communes](docs/screenshots/municipalities.jpg) |

| Codes postaux | Planification | Réglages | Introduction |
|---|---|---|---|
| ![Codes postaux](docs/screenshots/postcodes.jpg) | ![Planification](docs/screenshots/planning.jpg) | ![Réglages](docs/screenshots/settings.jpg) | ![Introduction](docs/screenshots/intro.jpg) |

**iPad**

| Tuiles | Planification |
|---|---|
| ![Tuiles iPad](docs/screenshots/ipad-tiles.jpg) | ![Planification iPad](docs/screenshots/ipad-planning.jpg) |

*Les captures utilisent des sorties de démonstration générées autour d’Utrecht, pas de vraies activités.*

## Pays

| Pays | Communes | Codes postaux |
|---|---|---|
| Pays-Bas | 342 gemeenten | 4 071 (PC4) |
| Belgique | 565 | 1 150 |
| Luxembourg | 100 communes | – |

Les codes postaux ne sont inclus que là où leurs limites sont publiées en données ouvertes. Les pays s’activent automatiquement selon vos activités ; vous pouvez les modifier dans Réglages.

## Pour commencer

Prérequis : Xcode 27 ou plus récent, iOS/iPadOS 26 ou plus récent, et un compte Apple Developer payant pour signer (nécessaire pour iCloud et les asset packs hébergés par Apple).

1. Clonez le dépôt et ouvrez `Tileroam.xcodeproj`.
2. Pour les cibles **Tileroam** et **TileroamWidget**, choisissez votre équipe sous *Signing & Capabilities*. Remplacez l’identifiant de bundle (`nl.petervanmanen.Tileroam`) et l’App Group (`group.nl.petervanmanen.Tileroam`) par les vôtres.
3. Facultatif, pour Strava : voir ci-dessous.
4. Lancez l’app sur votre iPhone ou iPad. Au premier lancement, choisissez un ou plusieurs dossiers iCloud Drive contenant vos fichiers `.fit`. Vous pourrez ajouter ou retirer des dossiers dans *Réglages → Dossiers d’import*.

### Strava (facultatif)

La connexion passe par l’**app Strava** (un toucher sur *Authorize*) ou, sans l’app Strava, par la connexion web de Strava. Le Client Secret reste sur un petit **service de jetons** ([`backend/strava-auth`](backend/strava-auth), un Cloudflare Worker) ; l’app ne contient que le Client ID.

1. Créez une application API sur [strava.com/settings/api](https://www.strava.com/settings/api) avec `localhost` comme *Authorization Callback Domain*.
2. Déployez le service de jetons comme décrit dans [`backend/strava-auth/README.md`](backend/strava-auth/README.md).
3. Copiez `StravaConfig.example.plist` vers `Tileroam/StravaConfig.plist` et renseignez `ClientID` et `TokenServiceURL` (l’URL du Worker se terminant par `/token`). Aucune des deux valeurs n’est secrète ; le fichier est dans `.gitignore` car c’est votre propre configuration.
4. Compilez et lancez l’app, puis touchez *Connect with Strava*.

Le Client Secret n’est stocké que dans le service de jetons, jamais dans l’app. Strava fait partie des builds Debug et Release grâce à la condition de compilation `STRAVA` ; retirez-la des *Active Compilation Conditions* pour compiler sans Strava. Pour d’autres utilisateurs, Strava doit d’abord augmenter la limite d’athlètes de votre application (un seul par défaut).

Strava autorise environ 100 requêtes par 15 minutes et 1 000 par jour. La liste des activités arrive vite avec des tracés simplifiés ; le GPS détaillé est complété ensuite et la synchronisation reprend automatiquement.

## Fonctionnement

- Les **fichiers FIT** sont lus par un petit décodeur intégré (`FIT/FITDecoder.swift`). Tracés, tuiles et zones visitées sont mis en cache ; au lancement suivant, seuls les fichiers nouveaux ou modifiés sont lus.
- Les **tuiles** utilisent la formule standard des tuiles Web Mercator (`Geo/TileGrid.swift`). Le carré max et le cluster sont calculés uniquement sur les tuiles visitées, ce qui reste rapide même pour des tuiles zoom 17 réparties dans toute l’Europe.
- **Doublons** : les activités du même type qui se chevauchent dans le temps sont fusionnées (`Import/ActivityMerge.swift`) ; la copie au meilleur GPS et à la plus longue distance est conservée.
- Les **communes et codes postaux** sont des fichiers binaires compacts (`AssetPacks/Regions/*.fmr`, 33 Mo au total) avec un index spatial pour des recherches rapides. Ils ne sont pas dans l’app : chaque pays est un asset pack hébergé par Apple (`regions-NL`, …) que l’app télécharge avec Background Assets dès que vous y avez une activité. `Tools/build_asset_packs.sh` les prépare pour App Store Connect ; dans le simulateur, `-RegionsDir <repo>/AssetPacks/Regions` les lit directement.
- La **planification** utilise le calculateur d’itinéraires vélo public [OSRM](https://project-osrm.org) d’[openstreetmap.de](https://routing.openstreetmap.de). Il détermine le meilleur ordre de visite, puis Tileroam choisit, dans chaque cible, le point qui minimise le détour.

## Données des limites

Les fichiers de limites sont générés par `Tools/build_regions.py` à partir des sources ouvertes listées dans *Réglages → Sources et licences* :

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <dossier-de-téléchargement> AssetPacks/Regions
```

Le script indique l’origine de chaque fichier source. Il reprojette en WGS84, fusionne les parties par code, simplifie les limites à ~25 m (communes) ou ~20 m (codes postaux) et écrit le format compact.

| Pays | Source et licence |
|---|---|
| Pays-Bas | CBS / Kadaster via PDOK (CC BY 4.0) |
| Belgique | NGI-IGN, bpost via Opendatasoft (licence des codes postaux : voir la source) |
| Luxembourg | ACT (CC0) |

Planification : © contributeurs OpenStreetMap (ODbL), itinéraires par OSRM / FOSSGIS.

## Confidentialité

Tileroam n’a ni serveur ni outil d’analyse. Vos activités, tuiles et statistiques restent sur votre appareil et dans les dossiers iCloud que vous choisissez. Les jetons Strava sont stockés dans le trousseau. Le code de connexion Strava et le renouvellement des jetons passent par le service de jetons (Cloudflare Worker), qui ne stocke ni ne journalise rien. Lorsque vous planifiez un parcours, le point de départ et les étapes sont envoyés au service d’itinéraires OSRM d’openstreetmap.de.

## Structure du projet

```
Tileroam/
  FIT/          décodeur et encodeur FIT
  Geo/          tuiles, communes/codes postaux, Eddington, simplification
  Import/       accès aux dossiers, import, cache, fusion des doublons, ActivityStore
  Map/          enveloppe MKMapView et couches (tuiles, zones, parcours)
  Planning/     planification (OSRM), GPX, couverture
  Strava/       client API Strava, export en .fit
  Views/        écrans SwiftUI (carte, réglages, introduction, panneau de planification)
  (AssetPacks/Regions/ limites des communes et codes postaux, en asset packs)
TileroamWidget/   widget Eddington
TileroamTests/    tests unitaires (Swift Testing)
Tools/             script et sources des données de limites
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Limites

- Les limites des codes postaux ne sont pas des données ouvertes en Autriche, au Luxembourg, en Irlande, au Portugal, en Italie, en Norvège, en Suède et en Islande.
- Les zones de codes postaux françaises sont des contours calculés autour des adresses et peuvent se chevaucher.
- Les postcode districts britanniques (2018) et les codes postaux espagnols (vers 2015) sont des jeux de données plus anciens.
- La planification dépend du serveur OSRM public, un service communautaire gratuit sans garantie.

## Licence

Le code source est sous [licence MIT](LICENSE). Les données de limites incluses conservent les licences de leurs sources (CC BY, OGL, Licence Ouverte, ODbL et autres) ; voir [DATA-LICENSES.md](DATA-LICENSES.md).
