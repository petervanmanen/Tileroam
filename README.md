# Tileroam

**English** · [Nederlands](README.nl.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam is an iPhone and iPad app that shows everywhere you have been on your rides, runs and walks: every map tile, municipality and postcode area you have visited. It reads `.fit` files from one or more iCloud Drive folders (for example exports from HealthFit, Garmin or Wahoo) and can import your history from Strava. It also plans cycling routes to places you haven't been yet.

![Tileroam on iPhone: tiles, squadratinhos, municipalities and route planning](docs/screenshots/overview.jpg)

## Features

- **Tiles**: zoom 14 map tiles (~1.5 km, as on VeloViewer, StatsHunters and [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) and zoom 17 *squadratinhos* (~190 m, as on Squadrats). Both are always counted; you choose which one the map shows. Includes your **max square** and **max cluster**.
- **Routes**: all your activities on one map, coloured by sport.
- **Municipalities and postcodes** in 22 European countries, with visited/total per country.
- **Route planning**: tap unvisited tiles, municipalities or postcodes and Tileroam plans the shortest cycling round trip from your location through all of them. Share it as **GPX** or save it to your iCloud folder. You can also open an existing GPX to see which new places it would collect.
- **Strava**: import your full history with GPS. Activities are also saved as standard `.fit` files in a folder of your choice.
- **Duplicates merged**: the same workout recorded by several devices or apps (watch, Zwift, Strava, HealthFit) counts once.
- **Eddington number** for cycling and running, also as a Home Screen and Lock Screen **widget**.
- **iPad** layout with a side panel, all orientations and multitasking.
- Available in **English, Dutch, French, Spanish and German**.
- The map opens on your biggest cluster, so you start where you ride most.

## Screenshots

| Tiles (zoom 14) | Squadratinhos (zoom 17) | Routes | Municipalities |
|---|---|---|---|
| ![Tiles](docs/screenshots/tiles.jpg) | ![Squadratinhos](docs/screenshots/squadratinhos.jpg) | ![Routes](docs/screenshots/routes.jpg) | ![Municipalities](docs/screenshots/municipalities.jpg) |

| Postcodes | Route planning | Settings | Introduction |
|---|---|---|---|
| ![Postcodes](docs/screenshots/postcodes.jpg) | ![Route planning](docs/screenshots/planning.jpg) | ![Settings](docs/screenshots/settings.jpg) | ![Introduction](docs/screenshots/intro.jpg) |

**iPad**

| Tiles | Route planning |
|---|---|
| ![iPad tiles](docs/screenshots/ipad-tiles.jpg) | ![iPad route planning](docs/screenshots/ipad-planning.jpg) |

*Screenshots use generated demo rides around Utrecht, not real activity data.*

## Countries

| Country | Municipalities | Postcodes |
|---|---|---|
| Netherlands | 342 gemeenten | 4,071 (PC4) |
| Belgium | 565 | 1,150 |
| Luxembourg | 100 communes | – |
| Germany | 10,949 Gemeinden | 8,173 PLZ |
| France | 34,888 communes | 6,158 (approximate zones) |
| Spain | 8,223 municipios | 10,874 |
| Portugal | 308 concelhos | – |
| Italy | 7,904 comuni | – |
| Switzerland | 2,128 Gemeinden | 3,181 PLZ |
| Austria | 2,092 Gemeinden | – |
| Liechtenstein, Monaco, Andorra, San Marino, Vatican City | 11 / 1 / 7 / 9 / 1 | – |
| United Kingdom | 361 local authorities | 2,836 postcode districts |
| Ireland | 31 local authorities | – |
| Denmark | 98 kommuner | 592 |
| Norway | 357 kommuner | – |
| Sweden | 290 kommuner | – |
| Finland | 308 kunnat | 3,026 |
| Iceland | 61 sveitarfélög | – |

Postcodes are only included where their boundaries are published as open data. Countries switch on automatically based on your activities; you can change them in Settings.

## Getting started

Requirements: Xcode 27 or later, iOS/iPadOS 18 or later, an Apple ID for signing (a free account works; apps then expire after 7 days).

1. Clone the repository and open `Tileroam.xcodeproj`.
2. Select the **Tileroam** and **TileroamWidget** targets, and choose your team under *Signing & Capabilities*. Change the bundle identifier (`nl.petervanmanen.Tileroam`) and the App Group (`group.nl.petervanmanen.Tileroam`) to your own.
3. Optional, for Strava: see below.
4. Run on your iPhone or iPad. On first launch, choose one or more iCloud Drive folders with your `.fit` files. You can add or remove folders later in *Settings → Import Folders*.

### Strava (optional)

Strava is only included in **development builds**: the `STRAVA` compilation condition is set for the Debug configuration. Release builds (Archive for TestFlight and the App Store) contain no Strava screens, make no Strava requests and leave out `StravaSecrets.plist`. To include Strava in a Release build, add `STRAVA` to *Active Compilation Conditions* for Release.


1. Create an API application at [strava.com/settings/api](https://www.strava.com/settings/api) with *Authorization Callback Domain* `localhost`.
2. Copy `StravaSecrets.example.plist` to `Tileroam/StravaSecrets.plist` and fill in `ClientID` and `ClientSecret`. This file is in `.gitignore`.
3. Build and run, then choose *Connect with Strava* in Settings.

The app talks to the Strava API directly, with the Client Secret inside the app. That is fine for personal use with your own API application. For public distribution, move the token exchange to a small server so the secret is not shipped in the app, and ask Strava to raise your application's athlete limit.

Strava allows about 100 requests per 15 minutes and 1,000 per day. The activity list arrives quickly with simplified routes; detailed GPS is filled in over time and the sync continues automatically.

## How it works

- **FIT files** are decoded by a small built-in decoder (`FIT/FITDecoder.swift`). Parsed routes, tiles and visited areas are cached, so only new or changed files are read on the next launch.
- **Tiles** use the standard Web Mercator tile formula (`Geo/TileGrid.swift`). Max square and cluster are computed on the visited tiles only, so they stay fast even for zoom 17 tiles spread across Europe.
- **Duplicates**: activities of the same kind that overlap in time are merged (`Import/ActivityMerge.swift`); the copy with the best GPS and the longest distance is kept.
- **Municipalities and postcodes** are bundled as compact binary files (`Resources/Regions/*.fmr`, 33 MB in total) with a spatial index for fast lookups.
- **Route planning** uses the public [OSRM](https://project-osrm.org) cycling router of [openstreetmap.de](https://routing.openstreetmap.de). It finds the best visiting order, then picks, inside each target, the point that keeps the detour shortest.

## Region data

The boundary files are generated by `Tools/build_regions.py` from the open data sources listed in *Settings → Sources & Licenses*:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <download-dir> Tileroam/Resources/Regions
```

The script documents where each source file comes from. It reprojects to WGS84, merges parts per code, simplifies boundaries to ~25 m (municipalities) or ~20 m (postcodes) and writes the compact format.

| Country | Source and license |
|---|---|
| Netherlands | CBS / Kadaster via PDOK (CC BY 4.0) |
| Belgium | NGI-IGN, bpost via Opendatasoft (postcode licence: see source) |
| Germany | BKG (dl-de/by-2-0); postcodes © OpenStreetMap contributors (ODbL) |
| France | IGN, INSEE; postcode zones Etalab / BAN (Licence Ouverte 2.0) |
| Spain | IGN, CNIG, Correos (CC BY 4.0) |
| Portugal | Direção-Geral do Território (public domain) |
| Italy | ISTAT (CC BY 3.0) |
| Switzerland | swisstopo (opendata.swiss) |
| Austria | Statistik Austria (CC BY 4.0) |
| Luxembourg | ACT (CC0) |
| United Kingdom | ONS, OS (OGL v3.0); postcode districts (CC BY 4.0) |
| Ireland | Tailte Éireann (CC BY 4.0) |
| Denmark | SDFI / Klimadatastyrelsen DAGI |
| Norway | Kartverket (CC BY 4.0) |
| Sweden | © OpenStreetMap contributors (ODbL) |
| Finland | Statistics Finland (CC BY 4.0) |
| Iceland | Náttúrufræðistofnun Íslands (CC BY 4.0) |
| Microstates | geoBoundaries / © OpenStreetMap contributors (ODbL) |

Route planning: © OpenStreetMap contributors (ODbL), routing by OSRM / FOSSGIS.

## Privacy

Tileroam has no server and no analytics. Your activities, tiles and statistics stay on your device and in the iCloud folders you choose. Strava tokens are stored in the Keychain. When you plan a route, the start point and stops are sent to the OSRM routing service of openstreetmap.de.

## Project structure

```
Tileroam/
  FIT/          FIT decoder and encoder
  Geo/          tiles, municipalities/postcodes, Eddington, simplification
  Import/       folder access, import, cache, duplicate merging, ActivityStore
  Map/          MKMapView wrapper and overlays (tiles, areas, routes)
  Planning/     route planning (OSRM), GPX, coverage
  Strava/       Strava API client, export to .fit
  Views/        SwiftUI screens (map, settings, introduction, plan panel)
  Resources/Regions/   bundled municipality and postcode boundaries
TileroamWidget/   Eddington widget
TileroamTests/    unit tests (Swift Testing)
Tools/             data build script and sources
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Limitations

- Postcode boundaries are not open data in Austria, Luxembourg, Ireland, Portugal, Italy, Norway, Sweden and Iceland.
- French postcode zones are calculated outlines around addresses and can overlap.
- The UK postcode districts (2018) and Spanish postcodes (around 2015) are older datasets.
- Route planning depends on the public OSRM server, which is a free community service without guarantees.

## License

The source code is licensed under the [MIT License](LICENSE). The bundled boundary data keeps the licenses of its sources (CC BY, OGL, Licence Ouverte, ODbL and others); see [DATA-LICENSES.md](DATA-LICENSES.md).
