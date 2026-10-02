# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · **Français** · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam est une app pour iPhone et iPad qui montre partout où vous êtes allé lors de vos sorties à vélo, courses et marches : chaque tuile de carte, commune et zone de code postal visitée. Elle lit les fichiers `.fit` d’un ou plusieurs dossiers iCloud Drive (par exemple des exports HealthFit, Garmin ou Wahoo) et peut importer votre historique Strava. Elle planifie aussi des parcours à vélo vers des lieux où vous n’êtes pas encore allé.

![Tileroam sur iPhone : tuiles, squadratinhos, communes et planification](docs/screenshots/overview.jpg)

## Fonctionnalités

- **Tuiles** : tuiles de carte au zoom 14 (~1,5 km, comme sur VeloViewer, StatsHunters et [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) et *squadratinhos* au zoom 17 (~190 m, comme sur Squadrats). Les deux sont toujours comptés ; vous choisissez celui que la carte affiche. Avec votre **carré max** et votre **plus grand cluster**.
- **Parcours** : toutes vos activités sur une seule carte, colorées par sport.
- **Communes et codes postaux** aux Pays-Bas, en Belgique, au Luxembourg et en Allemagne, avec visités/total par pays.
- **Planification d’itinéraire** aux Pays-Bas, en Belgique, au Luxembourg et en Allemagne : touchez des tuiles, communes ou codes postaux non visités et Tileroam planifie la boucle à vélo la plus courte qui les relie tous. Elle part de votre position, ou d’un **point de départ** que vous recherchez ou choisissez par un appui long sur la carte (les départs récents sont mémorisés). Les itinéraires sont calculés **sur l’appareil**, donc la planification fonctionne aussi hors ligne une fois la zone téléchargée. Partagez l’itinéraire en **GPX** ou enregistrez-le dans votre dossier iCloud. Vous pouvez aussi ouvrir un GPX existant pour voir quels nouveaux lieux il permettrait de collecter.
- **Strava** : importez tout votre historique avec le GPS. Les activités sont aussi enregistrées en fichiers `.fit` standard dans le dossier de votre choix.
- **Doublons fusionnés** : une même séance enregistrée par plusieurs appareils ou apps (montre, Zwift, Strava, HealthFit) ne compte qu’une fois.
- **Widgets** : *Tuiles autour de vous* (une carte des tuiles près de vous) et *Nombre d’Eddington*, sur l’écran d’accueil et l’écran verrouillé.
- **Statistiques** : pays et communes visités, nombres d’Eddington pour le vélo, la marche et la course, et totaux par sport pour cette année et depuis le début.
- Les **sorties en intérieur et virtuelles** (Zwift, Rouvy, MyWhoosh, home trainer) comptent dans les statistiques mais restent hors de la carte, des tuiles, des communes et des codes postaux.
- **Stockage facultatif** : sans dossier choisi, Tileroam enregistre parcours et fichiers Strava dans son propre stockage (app Fichiers › Sur mon iPhone › Tileroam) et lit aussi les fichiers `.fit` de son dossier Import.
- **Réglages → Stockage** affiche les données cartographiques téléchargées et permet de les supprimer. Les téléchargements de cartes de plus de 25 Mo attendent le Wi-Fi, sauf si vous autorisez les données cellulaires.
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
| Allemagne | 10 949 Gemeinden | 8 173 (PLZ) |

Les tuiles, parcours et statistiques fonctionnent partout ; les communes, codes postaux et la planification couvrent ces quatre pays. Les codes postaux ne sont inclus que là où leurs limites sont publiées en données ouvertes. Les limites d’un pays sont téléchargées automatiquement dès que vous y avez une activité.

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
- Les **communes et codes postaux** sont des fichiers binaires compacts (`AssetPacks/Regions/*.fmr`, 6,3 Mo au total) avec un index spatial pour des recherches rapides. Ils ne sont pas dans l’app : chaque pays est un asset pack hébergé par Apple (`regions-NL`, …) que l’app télécharge avec Background Assets dès que vous y avez une activité. `Tools/build_asset_packs.sh` les prépare pour App Store Connect ; dans le simulateur, `-RegionsDir <repo>/AssetPacks/Regions` les lit directement.
- La **planification** fonctionne sur l’appareil avec [Valhalla](https://github.com/valhalla/valhalla), via [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), et des tuiles OpenStreetMap pour les Pays-Bas, la Belgique, le Luxembourg et l’Allemagne. Les tuiles sont sur Cloudflare R2 ; un plan ne télécharge que les tuiles Valhalla autour de lui (25 à 75 Mo, au lieu de 2,2 Go pour tout). Les téléchargements de plus de 25 Mo attendent le Wi-Fi (`MapDataDownloads`). L’ordre de passage est calculé sur les distances à vol d’oiseau (`TripSolver`, bien plus rapide qu’une matrice d’itinéraires sur l’appareil) ; ensuite, dans chaque cible, le planificateur choisit le point qui minimise le détour, et Valhalla calcule la boucle. Construire et envoyer les tuiles, ajouter des pays : [docs/ROUTING.md](docs/ROUTING.md).

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
| Allemagne | BKG VG250 (dl-de/by-2-0); codes postaux : OpenStreetMap (ODbL) |

Planification : © contributeurs OpenStreetMap (ODbL), itinéraires calculés par Valhalla sur l’appareil.

## Documentation

- [Guide d’utilisation](docs/MANUAL.md) (en anglais)
- [Assistance et FAQ](SUPPORT.md) (en anglais)
- [Dossier App Store](docs/appstore/README.md) : métadonnées, captures d’écran, réponses sur la confidentialité, notes pour la vérification

## Structure du projet

```
Tileroam/
  FIT/          décodeur et encodeur FIT
  Geo/          tuiles, communes/codes postaux, Eddington, simplification
  Import/       accès aux dossiers, import, cache, fusion des doublons, ActivityStore
  Map/          enveloppe MKMapView et calques (tuiles, zones, parcours)
  Planning/     planification (Valhalla sur l’appareil), données d’itinéraires, points de départ, GPX, couverture
  Strava/       client API Strava, événements webhook, export en .fit
  Views/        écrans SwiftUI (carte, réglages, stockage, introduction, panneau de planification)
TileroamAssets/   extension de téléchargement Background Assets
TileroamWidget/   widgets : Tuiles autour de vous, Nombre d’Eddington
TileroamTests/    tests unitaires (Swift Testing)
AssetPacks/       limites des communes et codes postaux, servies en asset packs
backend/          service de jetons Strava et file d’événements webhook (Cloudflare Worker)
Tools/            scripts pour les données, les itinéraires, les asset packs, les captures et les versions
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Limites

- Les communes, codes postaux et la planification couvrent uniquement les Pays-Bas, la Belgique, le Luxembourg et l’Allemagne. [docs/ROUTING.md](docs/ROUTING.md) explique comment ajouter des pays.
- Le Luxembourg n’a pas de limites de codes postaux en données ouvertes.
- Les itinéraires sont des boucles ; les trajets simples de A à B ne sont pas encore pris en charge.

## Confidentialité

Tileroam n’a ni comptes, ni outil d’analyse, ni pistage. Vos activités, tuiles et statistiques restent sur votre appareil et dans votre propre iCloud, et la planification se fait sur l’appareil. Les jetons Strava sont conservés dans le trousseau. Les serveurs sont le service de jetons Strava ([`backend/strava-auth`](backend/strava-auth)) : il échange le code de connexion sans conserver les jetons, et garde les événements webhook de Strava (numéros d’athlète et d’activité, 30 jours au plus) pour que l’app puisse supprimer les activités que vous avez supprimées sur Strava, et les données cartographiques de planification sur Cloudflare R2, qui ne journalise rien. Voir la [politique de confidentialité](PRIVACY.md) (en anglais).

## Licence

Le code source est sous [licence MIT](LICENSE). Les données de limites conservent les licences de leurs sources (CC BY 4.0, CC0, dl-de/by-2-0, ODbL et les licences de NGI et bpost), et les données d’itinéraires sont © contributeurs OpenStreetMap (ODbL) ; voir [DATA-LICENSES.md](DATA-LICENSES.md).
