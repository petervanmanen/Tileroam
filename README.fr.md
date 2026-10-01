# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · **Français** · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam est une app pour iPhone et iPad qui montre partout où vous êtes allé lors de vos sorties à vélo, courses et marches : chaque tuile de carte, commune et zone de code postal visitée. Elle lit les fichiers `.fit` d’un ou plusieurs dossiers iCloud Drive (par exemple des exports HealthFit, Garmin ou Wahoo) et peut importer votre historique Strava. Elle planifie aussi des parcours à vélo vers des lieux où vous n’êtes pas encore allé.

![Tileroam sur iPhone : tuiles, squadratinhos, communes et planification](docs/screenshots/overview.jpg)

## Fonctionnalités

- **Tuiles** : tuiles de carte au zoom 14 (~1,5 km, comme sur VeloViewer, StatsHunters et [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) et *squadratinhos* au zoom 17 (~190 m, comme sur Squadrats). Les deux sont toujours comptés ; vous choisissez celui que la carte affiche. Avec votre **carré max** et votre **plus grand cluster**.
- **Parcours** : toutes vos activités sur une seule carte, colorées par sport.
- **Communes et codes postaux** dans 22 pays européens, avec visités/total par pays.
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
| Allemagne | 10 949 Gemeinden | 8 173 PLZ |
| France | 34 888 communes | 6 158 (zones approximatives) |
| Espagne | 8 223 municipios | 10 874 |
| Portugal | 308 concelhos | – |
| Italie | 7 904 comuni | – |
| Suisse | 2 128 Gemeinden | 3 181 NPA |
| Autriche | 2 092 Gemeinden | – |
| Liechtenstein, Monaco, Andorre, Saint-Marin, Vatican | 11 / 1 / 7 / 9 / 1 | – |
| Royaume-Uni | 361 local authorities | 2 836 postcode districts |
| Irlande | 31 local authorities | – |
| Danemark | 98 kommuner | 592 |
| Norvège | 357 kommuner | – |
| Suède | 290 kommuner | – |
| Finlande | 308 kunnat | 3 026 |
| Islande | 61 sveitarfélög | – |

Les codes postaux ne sont inclus que là où leurs limites sont publiées en données ouvertes. Les pays s’activent automatiquement selon vos activités ; vous pouvez les modifier dans Réglages.

## Pour commencer

Prérequis : Xcode 27 ou plus récent, iOS/iPadOS 18 ou plus récent, un identifiant Apple pour signer (un compte gratuit fonctionne ; les apps expirent alors après 7 jours).

1. Clonez le dépôt et ouvrez `Tileroam.xcodeproj`.
2. Pour les cibles **Tileroam** et **TileroamWidget**, choisissez votre équipe sous *Signing & Capabilities*. Remplacez l’identifiant de bundle (`nl.petervanmanen.Tileroam`) et l’App Group (`group.nl.petervanmanen.Tileroam`) par les vôtres.
3. Facultatif, pour Strava : voir ci-dessous.
4. Lancez l’app sur votre iPhone ou iPad. Au premier lancement, choisissez un ou plusieurs dossiers iCloud Drive contenant vos fichiers `.fit`. Vous pourrez ajouter ou retirer des dossiers dans *Réglages → Dossiers d’import*.

### Strava (facultatif)

Strava n’est inclus que dans les **builds de développement** : la condition de compilation `STRAVA` est définie pour la configuration Debug. Les builds Release (Archive pour TestFlight et l’App Store) ne contiennent aucun écran Strava, n’effectuent aucune requête Strava et n’incluent pas `StravaSecrets.plist`. Pour inclure Strava dans un build Release, ajoutez `STRAVA` aux *Active Compilation Conditions* de Release.


1. Créez une application API sur [strava.com/settings/api](https://www.strava.com/settings/api) avec `localhost` comme *Authorization Callback Domain*.
2. Copiez `StravaSecrets.example.plist` vers `Tileroam/StravaSecrets.plist` et renseignez `ClientID` et `ClientSecret`. Ce fichier est dans `.gitignore`.
3. Compilez et lancez l’app, puis choisissez *Se connecter avec Strava* dans Réglages.

L’app communique directement avec l’API Strava, avec le Client Secret intégré à l’app. C’est acceptable pour un usage personnel avec votre propre application API. Pour une distribution publique, déplacez l’échange de jetons vers un petit serveur afin que le secret ne soit pas livré dans l’app, et demandez à Strava d’augmenter la limite d’athlètes de votre application.

Strava autorise environ 100 requêtes par 15 minutes et 1 000 par jour. La liste des activités arrive vite avec des tracés simplifiés ; le GPS détaillé est complété ensuite et la synchronisation reprend automatiquement.

## Fonctionnement

- Les **fichiers FIT** sont lus par un petit décodeur intégré (`FIT/FITDecoder.swift`). Tracés, tuiles et zones visitées sont mis en cache ; au lancement suivant, seuls les fichiers nouveaux ou modifiés sont lus.
- Les **tuiles** utilisent la formule standard des tuiles Web Mercator (`Geo/TileGrid.swift`). Le carré max et le cluster sont calculés uniquement sur les tuiles visitées, ce qui reste rapide même pour des tuiles zoom 17 réparties dans toute l’Europe.
- **Doublons** : les activités du même type qui se chevauchent dans le temps sont fusionnées (`Import/ActivityMerge.swift`) ; la copie au meilleur GPS et à la plus longue distance est conservée.
- Les **communes et codes postaux** sont intégrés sous forme de fichiers binaires compacts (`Resources/Regions/*.fmr`, 33 Mo au total) avec un index spatial pour des recherches rapides.
- La **planification** utilise le calculateur d’itinéraires vélo public [OSRM](https://project-osrm.org) d’[openstreetmap.de](https://routing.openstreetmap.de). Il détermine le meilleur ordre de visite, puis Tileroam choisit, dans chaque cible, le point qui minimise le détour.

## Données des limites

Les fichiers de limites sont générés par `Tools/build_regions.py` à partir des sources ouvertes listées dans *Réglages → Sources et licences* :

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <dossier-de-téléchargement> Tileroam/Resources/Regions
```

Le script indique l’origine de chaque fichier source. Il reprojette en WGS84, fusionne les parties par code, simplifie les limites à ~25 m (communes) ou ~20 m (codes postaux) et écrit le format compact.

| Pays | Source et licence |
|---|---|
| Pays-Bas | CBS / Kadaster via PDOK (CC BY 4.0) |
| Belgique | NGI-IGN, bpost via Opendatasoft (licence des codes postaux : voir la source) |
| Allemagne | BKG (dl-de/by-2-0) ; codes postaux © contributeurs OpenStreetMap (ODbL) |
| France | IGN, INSEE ; zones de codes postaux Etalab / BAN (Licence Ouverte 2.0) |
| Espagne | IGN, CNIG, Correos (CC BY 4.0) |
| Portugal | Direção-Geral do Território (domaine public) |
| Italie | ISTAT (CC BY 3.0) |
| Suisse | swisstopo (opendata.swiss) |
| Autriche | Statistik Austria (CC BY 4.0) |
| Luxembourg | ACT (CC0) |
| Royaume-Uni | ONS, OS (OGL v3.0) ; postcode districts (CC BY 4.0) |
| Irlande | Tailte Éireann (CC BY 4.0) |
| Danemark | SDFI / Klimadatastyrelsen DAGI |
| Norvège | Kartverket (CC BY 4.0) |
| Suède | © contributeurs OpenStreetMap (ODbL) |
| Finlande | Statistics Finland (CC BY 4.0) |
| Islande | Náttúrufræðistofnun Íslands (CC BY 4.0) |
| Micro-États | geoBoundaries / © contributeurs OpenStreetMap (ODbL) |

Planification : © contributeurs OpenStreetMap (ODbL), itinéraires par OSRM / FOSSGIS.

## Confidentialité

Tileroam n’a ni serveur ni outil d’analyse. Vos activités, tuiles et statistiques restent sur votre appareil et dans les dossiers iCloud que vous choisissez. Les jetons Strava sont stockés dans le trousseau. Lorsque vous planifiez un parcours, le point de départ et les étapes sont envoyés au service d’itinéraires OSRM d’openstreetmap.de.

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
  Resources/Regions/   limites des communes et codes postaux intégrées
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
