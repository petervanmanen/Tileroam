# On-device route planning

Tileroam plans cycling routes on the iPhone or iPad itself, with [Valhalla](https://github.com/valhalla/valhalla) and OpenStreetMap data. Nothing is sent to a server.

The routing data comes from [Geofabrik](https://download.geofabrik.de)'s OpenStreetMap extracts. It's built on a Mac into Valhalla tiles and split into Apple-hosted asset packs **per 1° × 1° area** (about 70 × 110 km), the same mechanism as the municipality and postcode boundaries. A plan downloads only the areas it needs.

Route planning currently covers **the Netherlands, Belgium and Luxembourg**: build `benelux`, 35 area packs plus a base pack, 487 MB together.

| Example plan | Download |
|---|---|
| Around Utrecht | about 60 MB: area `n52e005` plus the base pack |
| Around Bree | about 73 MB |
| Rural or coastal areas | often only a few MB |

## How it fits together

| Part | Where | What it does |
|---|---|---|
| Valhalla engine | Swift package [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), pinned to **0.6.3** in the Xcode project | Valhalla **3.6.3** compiled for iOS. Tileroam uses its `route` action with the `bicycle` costing. |
| Engine settings | `Tileroam/Resources/valhalla.json` | Valhalla's configuration, made with `valhalla_build_config` of the same version. At runtime `RoutingData.writeConfig` fills in the tile directory. The bicycle limit is raised to 60 locations, for 50 stops. |
| Routing data | asset packs `routing-benelux-<area>` (for example `routing-benelux-n52e005`, the area from 52°N 5°E) and `routing-benelux-base` | Each area pack holds Valhalla's level-1 tile (1°, through roads) and level-2 tiles (0.25°, all local roads and paths) of that area. The base pack holds the level-0 tiles (4°, main roads), which every plan needs. |
| Index | `Tileroam/Resources/routing-benelux.json` (bundled, committed) | Which areas exist, with their size and tile files. Written by `Tools/split_routing_tiles.py`; asset packs can't list their own contents. |
| Downloading | `RoutingData.packs(around:margin:)`, `RoutingData.tileDirectory` | Takes every area within 15 km of the bounding box of the start and the selected items, downloads those packs and the base pack where needed, and links their tiles into one folder for Valhalla (`Application Support/Routing/tiles-benelux`). If Valhalla still finds no route (a detour off the edge), the planner retries once with 60 km of room. All packs come from one build, so the tiles connect. |
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
Tools/build_routing_tiles.sh benelux netherlands belgium luxembourg
```

The first argument names the pack; the others are Geofabrik extract names under `europe/`. The script:

1. **Downloads** the extracts to `AssetPacks/build/routing/osm/`. It downloads them again when they're older than a week. The Netherlands is about 1.4 GB, Belgium 0.7 GB, Luxembourg 50 MB.
2. **Merges** them with `osmium merge`. Country extracts overlap at the borders; building them separately would duplicate the border roads.
3. **Builds Valhalla's tiles** with `valhalla_build_tiles`. Left out, because cycling routes don't need them:
   - time zone, admin and traffic data;
   - car-only roads, driveways and car shortcuts (about 10% smaller).

   Footpaths stay in, so routes can cross pedestrian zones with the bike pushed. `ROUTING_PEDESTRIAN=False Tools/build_routing_tiles.sh …` drops them too, about 25% smaller in total, but then routes can't use pedestrian-only paths.
4. **Writes one tile extract** with all tiles, `AssetPacks/build/routing/routing-benelux.tar` (`valhalla_build_extract`). It's for the simulator and screenshots only; it isn't uploaded.
5. **Splits the tiles per 1° area** (`Tools/split_routing_tiles.py`):
   - writes the index `Tileroam/Resources/routing-benelux.json` (commit it with the app);
   - packages the asset packs `AssetPacks/build/routing-benelux-<area>.aar` and `routing-benelux-base.aar`, all downloaded on demand.

   Test builds named `<name>-test` keep their index in the build folder instead.

Everything under `AssetPacks/build/` is ignored by Git. For Benelux, expect a few GB of temporary disk space and 10–20 minutes on an M-series Mac.

## Uploading

```bash
ASC_KEY_ID=<KeyID> ASC_ISSUER_ID=<IssuerID> Tools/upload_asset_packs.sh routing-benelux
```

This uploads all 36 packs of the build, using the App Store Connect API key in `~/.appstoreconnect/private_keys/` and Transporter. The packs then have to be available to the builds that use it: TestFlight right away, and the App Store together with the version under review. The GitHub *Asset packs* workflow only handles the boundary packs; routing data is built and uploaded from a Mac, because it needs the large downloads.

Refresh the data every few months, because OpenStreetMap changes. Run the build again, then upload **all** packs of the build and ship the new index with the next app version: tiles of different builds don't connect. Rebuilding can change which areas exist (rarely, for border or coast areas). An area that's new in the index but not yet uploaded would make planning there fail, so upload before releasing the app with the new index.

## Testing in the simulator

- **The app, like production:** launch the Debug build with `-RoutingPacksDir <repo>/AssetPacks/build/routing/packs-benelux`. The app then takes the area packs from the build folder instead of downloading them, links them and plans exactly as on a device.
- **The app, simplest:** `-RoutingTar <repo>/AssetPacks/build/routing/routing-benelux.tar` uses the one file with all tiles. The screenshot and preview scripts use this.
- **Without either,** the app tries to download the asset packs.
- **Engine tests:** `TileroamTests/ValhallaEngineTests.swift` runs Valhalla in the simulator on a small Luxembourg-only build: once from its tile extract, and once through its area packs, as in production. Make it with:
  ```bash
  Tools/build_routing_tiles.sh lu-test luxembourg
  ```
  Without that file, the engine tests are skipped, as on GitHub.
- **The rest:** the decoding and stop-ordering tests (`PlanningTests`) don't need any tiles.

## Adding countries

Example: adding Germany.

1. **Choose the build.** Countries whose routes should cross each other's borders must be in **one** build. Germany borders the Netherlands, Belgium and Luxembourg, so it joins that build under a new name, for example `west`. Because the data is split per 1° area, a bigger build doesn't make downloads bigger: a plan still only fetches its own areas.
2. **Mind the build itself.** Germany alone is about 4 GB of OpenStreetMap data. Expect more disk space (tens of GB of temporary files) and an hour or more of build time. Check how many asset packs you end up with (about one per 1° area with data): Apple may limit the number of asset packs per app.
3. **Build:**
   ```bash
   Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany
   ```
4. **Update the app:**
   - In `RoutingData.swift`: add the country codes to `RoutingData.countries`, and set `build` to `"west"`. The app then bundles `Resources/routing-west.json`; remove the old index file.
   - Update the text of `RoutingError.outsideRegion` in `Tileroam/Planning/Routing.swift`, and its translations in the string catalog.
   - Update `docs/MANUAL.md`, `docs/appstore/review-notes.md` and this document.
   - Regenerate the App Store's Routing App Coverage File and upload it on the next version page:
     ```bash
     <venv with shapely>/bin/python Tools/build_routing_coverage.py NL BE LU DE
     ```
     It writes `docs/appstore/routing-coverage.geojson`, following Apple's rules: at most 20 polygons of at most 20 points, closed, no holes. It's checked to contain every municipality of those countries.
5. **Test** in the simulator with `-RoutingPacksDir …/packs-west`: plan a route that crosses the new border.
6. **Upload** the new packs (`Tools/upload_asset_packs.sh routing-west`), then ship the app version that uses them. Keep the old packs in App Store Connect until no supported app version uses them any more.

Only countries with municipality boundaries in Tileroam (see `Country.all`) can be detected by the bundled outlines. For a country outside that list, first add its boundaries (`Tools/build_regions.py`, `Tools/build_country_outlines.py`).

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
