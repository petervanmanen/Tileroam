# Tileroam

**English** · [Nederlands](README.nl.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam is an iPhone and iPad app that shows everywhere you have been on your rides, runs and walks: every map tile, municipality and postcode area you have visited. It reads `.fit` files from one or more iCloud Drive folders (for example exports from HealthFit, Garmin or Wahoo) and can import your history from Strava. It also plans cycling routes to places you haven't been yet.

![Tileroam on iPhone: tiles, municipalities, climbs and route planning](docs/screenshots/overview.jpg)

## Features

- **Tiles**: zoom 14 map tiles (~1.5 km, as on VeloViewer, StatsHunters and [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) Includes your **max square** and **max cluster**.
- **Climbs**: every climb on the roads (Cat 4 to HC like Strava, and short steep hills), found from elevation data; which ones you have climbed, on a map tab and in Statistics, and climbs to include when planning a route. See [docs/CLIMBS.md](docs/CLIMBS.md).
- **Challenges**: besides tiles, turn on the challenges you like with the **+** at the top of the map: municipalities, postcodes, climbs, the **Trappist Challenge** (ride past the Trappist breweries; within 200 m counts), the **Boscafé Challenge** (53 cafés in the woods of the Netherlands; within 200 m counts), the **Klompenpaden** (the 167 walking paths of [www.klompenpaden.nl](https://www.klompenpaden.nl); walked when your activities cover 90% of a path), and the signposted **mountain bike routes** of OpenStreetMap (about 4,700). Hidden challenges still count.
- **Badges**: 18 badges, from *100!*, *Century* and *Everester* to *Festive 500*, *Triathlete* and *Globetrotter* (50 countries, worked out on the device). Earned badges are in colour, with how often; indoor activities count too.
- **Activities**: a list of all activities, newest first, with duration, distance and average power (with a power meter) or average speed.
- **Municipalities and postcodes** in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria, with visited/total per country.
- **Route planning** in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria: tap unvisited tiles, municipalities or postcodes and Tileroam plans the shortest cycling round trip through all of them, or a route from A to B to an **end point** you choose. It starts from your location, or from a **starting point** you search for or long-press on the map (recent starts are remembered). Routes are calculated **on the device**, so planning also works offline once an area is downloaded. Share the route as **GPX** or save it to your iCloud folder. You can also open an existing GPX to see which new places it would collect.
- **Strava**: import your full history with GPS. Activities are also saved as standard `.fit` files in a folder of your choice.
- **Duplicates merged**: the same workout recorded by several devices or apps (watch, Zwift, Strava, HealthFit) counts once.
- **Widgets**: *Tiles Around You* (a map of the tiles near you) and *Eddington Number*, on the Home Screen and Lock Screen.
- **Statistics**: countries and municipalities visited, Eddington numbers for cycling, walking and running, climbs, badges, and totals per sport for this year and all time; each category opens with a tap.
- **Indoor and virtual rides** (Zwift, Rouvy, MyWhoosh, trainer rides) count in the statistics but stay off the map, tiles, municipalities and postcodes.
- **Your own copy, synced with iCloud**: imported `.fit` files and Strava downloads are kept in the app (Files app › On My iPhone › Tileroam › Activities), and with iCloud sync also in iCloud Drive › Tileroam, without duplicates; a further device needs no setup. Imports are one-time copies. Activities can be deleted in the Activities list.
- **Settings → Storage** shows the downloaded map data and lets you remove it. Map downloads over 25 MB wait for Wi-Fi unless you allow mobile data.
- **iPad** layout with a side panel, all orientations and multitasking.
- **Mac** app (Mac Catalyst) with everything except route planning: the on-device router isn't built for the Mac.
- Available in **English, Dutch, French, Spanish and German**.
- The map opens on your biggest cluster, so you start where you ride most.

## Screenshots

| Tiles | Municipalities | Postcodes |
|---|---|---|
| ![Tiles](docs/screenshots/tiles.jpg) | ![Municipalities](docs/screenshots/municipalities.jpg) | ![Postcodes](docs/screenshots/postcodes.jpg) |

| Climbs | Trappist Challenge | Route planning |
|---|---|---|
| ![Climbs](docs/screenshots/climbs.jpg) | ![Trappist Challenge](docs/screenshots/trappists.jpg) | ![Route planning](docs/screenshots/planning.jpg) |

| Badges | Settings | Introduction |
|---|---|---|
| ![Badges](docs/screenshots/badges.jpg) | ![Settings](docs/screenshots/settings.jpg) | ![Introduction](docs/screenshots/intro.jpg) |

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
| Germany | 10,949 Gemeinden | 8,173 (PLZ) |
| France | 34,888 communes | 6,158 (approximate zones) |
| Switzerland | 2,128 Gemeinden | 3,181 PLZ |
| Austria | 2,092 Gemeinden | – |

Tiles, routes and statistics work everywhere; municipalities, postcodes and route planning cover these seven countries. Postcodes are only included where their boundaries are published as open data. A country's boundaries are downloaded automatically the first time you have an activity there.

## Getting started

Requirements: Xcode 27 or later, iOS/iPadOS 26 or later, and a paid Apple Developer account for signing (iCloud and Apple-hosted asset packs need one).

1. Clone the repository and open `Tileroam.xcodeproj`.
2. Select the **Tileroam** and **TileroamWidget** targets, and choose your team under *Signing & Capabilities*. Change the bundle identifier (`nl.petervanmanen.Tileroam`) and the App Group (`group.nl.petervanmanen.Tileroam`) to your own.
3. Optional, for Strava: see below.
4. Run on your iPhone or iPad. On first launch, import `.fit` files (or a folder of them), connect Strava or try the sample rides. You can import more later in *Settings → Activities*.

### Strava (optional)

Login goes through the **Strava app** (one tap on *Authorize*) or, without the Strava app, Strava's web login. The Client Secret stays on a small **token service** ([`backend/strava-auth`](backend/strava-auth), a Cloudflare Worker); the app itself only contains the Client ID.

1. Create an API application at [strava.com/settings/api](https://www.strava.com/settings/api) with *Authorization Callback Domain* `localhost`.
2. Deploy the token service as described in [`backend/strava-auth/README.md`](backend/strava-auth/README.md).
3. Copy `StravaConfig.example.plist` to `Tileroam/StravaConfig.plist` and fill in `ClientID`. It isn't secret; the file is in `.gitignore` because it is your own configuration. The token service's address is `StravaServiceURL` in `Tileroam/Servers.plist`, the one file with the app's servers (also the route planning tiles); put your Worker's URL there.
4. Build and run, then tap *Connect with Strava*.

The Client Secret is only stored in the token service, never in the app. Strava is part of both Debug and Release builds through the `STRAVA` compilation condition; remove it from *Active Compilation Conditions* to build without Strava. For other users, Strava must first raise your application's athlete limit (one athlete by default).

Strava allows about 100 requests per 15 minutes and 1,000 per day. The activity list arrives quickly with simplified routes; detailed GPS is filled in over time and the sync continues automatically.

## How it works

- **FIT files** are decoded by a small built-in decoder (`FIT/FITDecoder.swift`). Parsed routes, tiles and visited areas are cached, so only new or changed files are read on the next launch.
- **Storage** (`Import/Library.swift`): every activity and route lives in the app (`Documents/Activities`, `Documents/Routes`). With iCloud sync on, `Library.pull`/`push` mirror them to iCloud Drive › Tileroam, after duplicate files are removed (`ActivityMerge.preferredFile`). Deleted activities are remembered in iCloud's key-value store (`Deletions`), so other devices delete their copy and the Strava sync doesn't bring them back. Earlier versions' folders are copied in once (`Library.migrate`).
- **Tiles** use the standard Web Mercator tile formula (`Geo/TileGrid.swift`). Max square and cluster are computed on the visited tiles only, so they stay fast even for many tiles.
- **Duplicates**: activities of the same kind that overlap in time are merged (`Import/ActivityMerge.swift`); the copy with the best GPS and the longest distance is kept.
- **Municipalities and postcodes** are compact binary files (`AssetPacks/Regions/*.fmr`, 6.3 MB in total) with a spatial index for fast lookups. They're not in the app: each country is an Apple-hosted asset pack (`regions-NL`, …) that the app downloads with Background Assets the first time you have an activity there. `Tools/build_asset_packs.sh` packages them for upload to App Store Connect; in the simulator, `-RegionsDir <repo>/AssetPacks/Regions` reads them directly. Which countries to download comes from simplified country outlines bundled in the app (`Tileroam/Resources/countries.fmr`, 0.5 MB, made from the municipalities by `Tools/build_country_outlines.py`).
- **Route planning** runs on the device with [Valhalla](https://github.com/valhalla/valhalla), through [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), and OpenStreetMap tiles for the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria. The tiles are on Cloudflare R2; a plan downloads only Valhalla's tiles around it (25–75 MB, instead of 2.2 GB for everything). Downloads over 25 MB wait for Wi-Fi (`MapDataDownloads`). The visiting order is solved on straight-line distances (`TripSolver`, much faster than a routing matrix on the device); then, inside each target, the planner picks the point that keeps the detour shortest, and Valhalla routes the round trip. How to build and upload the tiles and add countries: [docs/ROUTING.md](docs/ROUTING.md).

## Region data

The boundary files are generated by `Tools/build_regions.py` from the open data sources listed in *Settings → Sources & Licenses*:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <download-dir> AssetPacks/Regions
```

The script documents where each source file comes from. It reprojects to WGS84, merges parts per code, simplifies boundaries to ~25 m (municipalities) or ~20 m (postcodes) and writes the compact format.

| Country | Source and license |
|---|---|
| Netherlands | CBS / Kadaster via PDOK (CC BY 4.0) |
| Belgium | NGI-IGN, bpost via Opendatasoft (postcode licence: see source) |
| Luxembourg | ACT (CC0) |
| Germany | BKG VG250 (dl-de/by-2-0); postcodes: OpenStreetMap (ODbL) |
| France | IGN, INSEE; postcode zones Etalab / BAN (Licence Ouverte 2.0) |
| Switzerland | swisstopo (opendata.swiss) |
| Austria | Statistik Austria (CC BY 4.0) |

Route planning: © OpenStreetMap contributors (ODbL), routing by Valhalla on the device.

## Documentation

- [User guide](docs/MANUAL.md)
- [Support and FAQ](SUPPORT.md)
- [App Store submission kit](docs/appstore/README.md): metadata, screenshots, privacy answers, review notes

## Project structure

```
Tileroam/
  FIT/          FIT decoder and encoder
  Geo/          tiles, municipalities/postcodes, Eddington, simplification
  Import/       folder access, import, cache, duplicate merging, ActivityStore
  Map/          MKMapView wrapper and overlays (tiles, areas, routes)
  Planning/     route planning (Valhalla on the device), routing data, starting points, GPX, coverage
  Strava/       Strava API client, webhook events, export to .fit
  Views/        SwiftUI screens (map, settings, storage, introduction, plan panel)
TileroamAssets/   Background Assets downloader extension
TileroamWidget/   widgets: Tiles Around You, Eddington Number
TileroamTests/    unit tests (Swift Testing)
AssetPacks/       municipality and postcode boundaries, served as asset packs
backend/          Strava token service and webhook event queue (Cloudflare Worker)
Tools/            data, routing, asset pack, screenshot and release scripts
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Limitations

- Municipalities, postcodes and route planning cover the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria only. [docs/ROUTING.md](docs/ROUTING.md) describes how to add countries.
- Luxembourg has no open postcode boundaries.

## Privacy

Tileroam has no accounts, analytics or tracking. Your activities, tiles and statistics stay on your device and in your own iCloud, and route planning runs on the device. Strava tokens are kept in the Keychain. The servers are the Strava token service ([`backend/strava-auth`](backend/strava-auth)): it exchanges the login code without storing tokens, and keeps Strava's webhook events (athlete and activity numbers, at most 30 days) so the app can delete activities you removed on Strava, and the route planning map data on Cloudflare R2, which keeps no logs. See the [privacy policy](PRIVACY.md).

## License

The source code is licensed under the [MIT License](LICENSE). The boundary data keeps the licenses of its sources (CC BY 4.0, CC0, dl-de/by-2-0, ODbL and the NGI and bpost licences), and the routing data is © OpenStreetMap contributors (ODbL); see [DATA-LICENSES.md](DATA-LICENSES.md).
