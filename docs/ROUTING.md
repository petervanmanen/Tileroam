# On-device route planning

Tileroam plans cycling routes on the iPhone or iPad itself, with [Valhalla](https://github.com/valhalla/valhalla) and OpenStreetMap data. Nothing is sent to a server.

The routing data comes from [Geofabrik](https://download.geofabrik.de)'s OpenStreetMap extracts. It's built on a Mac into Valhalla tiles and split into Apple-hosted asset packs **per 1° × 1° area** (about 70 × 110 km), the same mechanism as the municipality and postcode boundaries. A plan downloads only the areas it needs.

Route planning currently covers **the Netherlands, Belgium, Luxembourg and Germany**: build `west`, 91 area packs plus a base pack, 2.3 GB together.

| Example plan | Download |
|---|---|
| Around Bree, Munich or Hamburg (one area) | about 100 MB: the area plus the base pack (36 MB) |
| Around Utrecht or Cologne (where four areas meet) | about 300 MB |
| Rural or coastal areas | often only a few MB |

## How it fits together

| Part | Where | What it does |
|---|---|---|
| Valhalla engine | Swift package [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), pinned to **0.6.3** in the Xcode project | Valhalla **3.6.3** compiled for iOS. Tileroam uses its `route` action with the `bicycle` costing. |
| Engine settings | `Tileroam/Resources/valhalla.json` | Valhalla's configuration, made with `valhalla_build_config` of the same version. At runtime `RoutingData.writeConfig` fills in the tile directory. The bicycle limit is raised to 60 locations, for 50 stops. |
| Routing data | asset packs `routing-west-<area>` (for example `routing-west-n52e005`, the area from 52°N 5°E) and `routing-west-base` | Each area pack holds Valhalla's level-1 tile (1°, through roads) and level-2 tiles (0.25°, all local roads and paths) of that area. The base pack holds the level-0 tiles (4°, main roads), which every plan needs. |
| Index | `Tileroam/Resources/routing-west.json` (bundled, committed) | Which areas exist, with their size and tile files. Written by `Tools/split_routing_tiles.py`; asset packs can't list their own contents. |
| Downloading | `RoutingData.packs(around:margin:)`, `RoutingData.tileDirectory` | Takes every area within 15 km of the bounding box of the start and the selected items, downloads those packs and the base pack where needed, and links their tiles into one folder for Valhalla (`Application Support/Routing/tiles-west`). If Valhalla still finds no route (a detour off the edge), the planner retries once with 60 km of room. All packs come from one build, so the tiles connect. |
| Covered countries | `RoutingData.countries` in `Tileroam/Planning/RoutingData.swift` | Planning is refused with a clear message when the start or a selected item lies outside these countries. The bundled country outlines decide this. |
| Router | `Tileroam/Planning/ValhallaRouter.swift` | Stop order: `TripSolver` (nearest neighbour, 2-opt, relocation) on straight-line distances. Valhalla's cycling-time matrix gives nearly the same order but took 22 s for 30 stops on a Mac. The route: one `route` call with all stops as `break` locations. |
| Planner | `Tileroam/Planning/RoutePlanner.swift` | Picks a point inside each target, orders the stops, routes, and retries when a stop snaps outside its target. |

**Version coupling:** tiles are only guaranteed to load in the Valhalla version that built them. When you update valhalla-mobile, check which Valhalla version it contains (its README badge), then:
1. set the same version as `VALHALLA_VERSION` in `Tools/build_routing_tiles.sh`;
2. update `Tools/valhalla_build_extract.py` from that Valhalla tag;
3. regenerate `Tileroam/Resources/valhalla.json` (see below);
4. rebuild and re-upload the routing pack.

## One-time setup on the Mac

```bash
brew install python@3.12 osmium-tool
```

`Tools/build_routing_tiles.sh` creates its own Python environment with `pyvalhalla` (Valhalla's official tools), in `AssetPacks/build/routing/venv`. Nothing else is needed. The build works on Apple Silicon Macs.

## Building the routing data

```bash
Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany
```

The first argument names the pack; the others are Geofabrik extract names under `europe/`. The script:

1. **Downloads** the extracts to `AssetPacks/build/routing/osm/`. It downloads them again when they're older than a week. The Netherlands is about 1.4 GB, Belgium 0.7 GB, Luxembourg 50 MB.
2. **Merges** them with `osmium merge`. Country extracts overlap at the borders; building them separately would duplicate the border roads.
3. **Builds Valhalla's tiles** with `valhalla_build_tiles`. Left out, because cycling routes don't need them:
   - time zone, admin and traffic data;
   - car-only roads, driveways and car shortcuts (about 10% smaller).

   Footpaths stay in, so routes can cross pedestrian zones with the bike pushed. `ROUTING_PEDESTRIAN=False Tools/build_routing_tiles.sh …` drops them too, about 25% smaller in total, but then routes can't use pedestrian-only paths.
4. **Writes one tile extract** with all tiles, `AssetPacks/build/routing/routing-west.tar` (`valhalla_build_extract`). It's for the simulator and screenshots only; it isn't uploaded.
5. **Splits the tiles per 1° area** (`Tools/split_routing_tiles.py`):
   - writes the index `Tileroam/Resources/routing-west.json` (commit it with the app);
   - packages the asset packs `AssetPacks/build/routing-west-<area>.aar` and `routing-west-base.aar`, all downloaded on demand;
   - leaves out tiles more than 70 km from the covered countries (`Tools/routing_area_filter.py`, with the country outlines the app bundles). Planning never needs them: plans start and stop in those countries and download at most 60 km around. Germany's extract, for example, reaches 60°N and 25°E through its ferry routes; that would be 38 nearly empty packs. The countries come from `RoutingData.countries` (or `ROUTING_COUNTRIES="NL BE LU DE"`).

   `ROUTING_REPACK=1 Tools/build_routing_tiles.sh west` redoes only this step from the last build, without downloading or building again (a minute instead of hours).

   Test builds named `<name>-test` keep their index in the build folder instead.

Everything under `AssetPacks/build/` is ignored by Git. What the `west` build took on an M-series Mac with 8 GB of memory (`ROUTING_CONCURRENCY=4`, to spare memory):
- **Time:** about 1½ hours: 20 minutes downloading Germany (4.9 GB), an hour building the tiles.
- **Disk:** about 40 GB at the peak: the extracts (7 GB), the merged extract (7 GB, deleted after the tile build), Valhalla's temporary files (about 20 GB, deleted at the end), the tiles (5 GB), the tile extract (5.7 GB) and the packs (2.3 GB).
- An external disk formatted as FAT32 (MS-DOS) can't hold files over 4 GB, so it can't take the extracts or the tile extract.

## Uploading

```bash
ASC_KEY_ID=<KeyID> ASC_ISSUER_ID=<IssuerID> Tools/upload_asset_packs.sh routing-west
```

This uploads all 92 packs of the build (base first, with a `[n/92]` counter). If the upload stops halfway, `Tools/upload_asset_packs.sh --resume routing-west` uploads only the packs App Store Connect doesn't have yet. Don't use `--resume` after rebuilding an existing build: then every pack needs its new version. The upload works with the App Store Connect API key in `~/.appstoreconnect/private_keys/` and Transporter. The packs then have to be available to the builds that use it: TestFlight right away, and the App Store together with the version under review. The GitHub *Asset packs* workflow only handles the boundary packs; routing data is built and uploaded from a Mac, because it needs the large downloads.

Refresh the data every few months, because OpenStreetMap changes: run the same build again (same name), upload **all** its packs, and ship the new index with the next app version. That makes a new **version** of the data; see below.

## Versions

**Keep the build name `west`, for good.** Adding a country or refreshing the data is a new version of the same build, uploaded as new versions of the same pack IDs. A new build name would need a complete second set of packs next to the old one until old app versions are gone, and Apple's limit of 100 asset packs per app doesn't leave room for that (`west` alone is 92). The name is internal; it doesn't have to match the countries.

**Why versions matter:** tiles of different builds don't connect, because Valhalla numbers its graph per build. Once new versions are uploaded, the system hands out the new version for every pack a device downloads from then on, also to app versions with the old index. Without a check, a device could link old and new packs together and get broken routes.

**How it works:**
- **The version number:**
  - `Tools/build_routing_tiles.sh` raises it by one per build, starting from the bundled index (`"version"` in `Resources/routing-west.json`; an index without it is version 1).
  - A repack (`ROUTING_REPACK=1`) keeps it; `ROUTING_VERSION=<n>` overrides it.
- **In each pack:** `Tools/split_routing_tiles.py` writes the version into the index and into every pack, as the file `version/<pack ID>`. The packs of version 1 (the first `west` upload, 2 October 2026) have no such file and count as version 1.
- **On the device:** the tile directory remembers the version of its links (`Application Support/Routing/tiles-west/.version`).
- **Before linking** (`RoutingData.tileDirectory(for:index:)`), the app compares the needed packs' versions, the linked version and the index's version (`RoutingData.versionCheck`):
  - **All the same, and not older than the index:** use them.
  - **Mixed, or older than the index:** remove every pack of the build from the device and the tile directory, then download the needed packs again in their latest version (`requireLatestVersion: true`). The router forgets what it loaded. If the versions are still mixed (an upload in progress), planning says to try again later.
- **An app version with an older index** on newer packs: it plans with the new packs, as long as they all have one version, but links only the tiles its own index lists. Tiles that are new in the newer build stay unused until the app updates. Fine for refreshes; for a new country, the old app doesn't allow planning there anyway (`RoutingData.countries`).

**The order for a new version:**
1. Build (the version goes up by one) and test.
2. Upload **all** packs (`Tools/upload_asset_packs.sh routing-west`, without `--resume`: every pack needs its new version). From then on, devices get the new version for anything they download.
3. Release the app version with the new index. On its first plan, a device replaces older data in one go.
4. Areas that are new in a version (a new country) are new pack IDs, so the pack count only grows by those.

## Testing in the simulator

- **The app, like production:** launch the Debug build with `-RoutingPacksDir <repo>/AssetPacks/build/routing/packs-west`. The app then takes the area packs from the build folder instead of downloading them, links them and plans exactly as on a device.
- **The app, simplest:** `-RoutingTar <repo>/AssetPacks/build/routing/routing-west.tar` uses the one file with all tiles. The screenshot and preview scripts use this.
- **Without either,** the app tries to download the asset packs.
- **Engine tests:** `TileroamTests/ValhallaEngineTests.swift` runs Valhalla in the simulator on a small Luxembourg-only build: once from its tile extract, and once through its area packs, as in production. Make it with:
  ```bash
  Tools/build_routing_tiles.sh lu-test luxembourg
  ```
  Without that file, the engine tests are skipped, as on GitHub.
- **The rest:** the decoding and stop-ordering tests (`PlanningTests`) don't need any tiles.

## Adding countries

Germany was added this way (October 2026). For the next country:

1. **Use build `west`.** Countries whose routes should cross each other's borders must be in **one** build, and `west` keeps its name (see "Versions"): the new country makes a new version of it. Because the data is split per 1° area, a bigger build doesn't make downloads bigger: a plan still only fetches its own areas.
2. **Check the limits first:**
   - **Asset packs:** App Store Connect refused uploads beyond **100 asset packs** for Tileroam (October 2026), although [Apple's limits page](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-size-limits/) says 200. Archived packs don't count. Tileroam uses 96: `west` (92) and the boundary packs of the four countries. **A new country doesn't fit as it is** (Austria would add about 15 areas). First make the packs bigger: for example 2° × 1° or 2° × 2° areas in `split_routing_tiles.py`, or merging the many small border and coast areas into their neighbours. The app reads which areas exist from the index, so it would need `RoutingIndex.Area` to carry a width and height instead of the fixed 1°.
   - **Disk and time:** see "Building the routing data" above.
3. **Boundaries:** the country needs municipality boundaries in Tileroam first:
   - `Tools/build_regions.py` for its `AssetPacks/Regions/<CC>-*.fmr`, plus its entry in `regions.json`;
   - add it to `Country.all` in `Tileroam/Geo/Regions.swift` and to Sources & Licenses in `SettingsView`;
   - rebuild the country outlines (`Tools/build_country_outlines.py`), which decide where planning is allowed;
   - upload its boundary pack (`Tools/upload_asset_packs.sh <CC>`), unless it's already in App Store Connect (as `regions-DE` was).
4. **The app:**
   - Add the country code to `RoutingData.countries` (the build reads it too, for the reach filter).
   - Don't change `RoutingData.build`. (`RoutingData.retiredBuilds` removes the packs of the one earlier build, `benelux`, from devices.)
   - Texts naming the countries: `RoutingError.outsideRegion` (`Tileroam/Planning/Routing.swift`), the introduction (`IntroView`), and their translations in the string catalog. The starting point search region is `PlaceSearch.region` (`StartPoint.swift`).
   - The tests that list the countries (`GeoTests`, `CountryTests`).
   - Docs: the READMEs, `docs/MANUAL.md`, `SUPPORT.md`, the App Store texts and review notes, `DATA-LICENSES.md` and this document.
   - Once Tileroam is an Apple Maps routing app (not in 1.0), regenerate the Routing App Coverage File:
     ```bash
     <venv with shapely>/bin/python Tools/build_routing_coverage.py NL BE LU DE
     ```
5. **Build and test:**
   ```bash
   ROUTING_CONCURRENCY=4 Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany
   ```
   - `WestRoutingTests` in `TileroamTests/ValhallaEngineTests.swift` routes Kerkrade → Aachen across the border on the new tile extract. Add a route across the new border there.
   - In the simulator: `-RoutingPacksDir <repo>/AssetPacks/build/routing/packs-west -RegionsDir <repo>/AssetPacks/Regions -PlanDemo YES -PlanDemoStart "50.8687,6.0835"` plans the demo route from any start, here on the Dutch–German border in Kerkrade.
6. **Upload all** packs (`Tools/upload_asset_packs.sh routing-west`, without `--resume`) **before** releasing the app version with the new index, as in "Versions".

## Regenerating `valhalla.json`

```bash
AssetPacks/build/routing/venv/bin/python -m valhalla.valhalla_build_config --mjolnir-tile-dir "" --mjolnir-tile-extract TILE_EXTRACT --mjolnir-traffic-extract "" --mjolnir-timezone "" --mjolnir-admin "" --mjolnir-landmarks "" --additional-data-elevation "" > Tileroam/Resources/valhalla.json
```

Then set `service_limits.bicycle.max_locations` to 60 again.

## Licenses

- **The routing data** is a Derivative Database of OpenStreetMap: ODbL 1.0, © OpenStreetMap contributors. `Tools/build_routing_tiles.sh` and the Geofabrik extracts it names are the full recipe to rebuild it.
- **Valhalla** and **valhalla-mobile** are MIT licensed.
- **`Tools/valhalla_build_extract.py`** is Valhalla's own script, MIT licensed.
- **Planned routes, including GPX exports,** are © OpenStreetMap contributors (ODbL). The attribution is in the app under Settings → Sources & Licenses.
