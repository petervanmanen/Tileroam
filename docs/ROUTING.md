# On-device route planning

Tileroam plans cycling routes on the iPhone or iPad itself, with [Valhalla](https://github.com/valhalla/valhalla) and OpenStreetMap data. The route, its start and its stops never leave the device; only the map data around a plan is downloaded.

The routing data comes from [Geofabrik](https://download.geofabrik.de)'s OpenStreetMap extracts. It's built on a Mac into Valhalla tiles, gzipped per tile and put on **Cloudflare R2**, from where the app downloads only the tiles around a plan. (Until October 2026 the tiles came as Apple-hosted asset packs per 1° area; see "Why R2" below.)

Route planning currently covers **the Netherlands, Belgium, Luxembourg and Germany**: build `west`, version 1, 1,179 tiles, 2.2 GB compressed on R2.

| Example plan (15 km around one point) | Download |
|---|---|
| Ardennes (rural) | about 26 MB |
| Bree, Hamburg, Munich | about 40–50 MB |
| Utrecht, Berlin, Cologne (cities) | about 55–75 MB |

Most of it is level 2, the local roads and paths of the 0.25° tiles around the plan; a level-0 main road tile (4°) is up to 11 MB.

## How it fits together

| Part | Where | What it does |
|---|---|---|
| Valhalla engine | Swift package [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), pinned to **0.6.3** in the Xcode project | Valhalla **3.6.3** compiled for iOS. Tileroam uses its `route` action with the `bicycle` costing. |
| Engine settings | `Tileroam/Resources/valhalla.json` | Valhalla's configuration, made with `valhalla_build_config` of the same version. At runtime `RoutingData.writeConfig` fills in the tile directory. The bicycle limit is raised to 60 locations, for 50 stops. |
| Routing data | Cloudflare R2: `<server>/west/v<version>/<tile>.gph.gz`, for example `west/v1/2/000/791/223.gph.gz` | Valhalla's tiles as they are: level 0 (4°, main roads), level 1 (1°, through roads) and level 2 (0.25°, all local roads and paths), each gzipped and served with `Content-Encoding: gzip`. `RoutingData.server` is the bucket's public URL. |
| Index | `Tileroam/Resources/routing-west.json` (bundled, committed) | The build's name and version, and every tile with its compressed and uncompressed size. Written by `Tools/pack_routing_tiles.py`. |
| Downloading | `RoutingData.tiles(around:margin:in:)`, `RoutingData.download(_:index:)` | Takes the tiles of every level that overlap the bounding box of the start and the selected items, widened by 15 km, downloads the missing ones (six at a time, over HTTPS) and decompresses them into `Application Support/Routing/west-v<version>`. Each tile's size is checked against the index. If Valhalla still finds no route (a detour off the edge), the planner retries once with 60 km of room. |
| Wi-Fi rule | `MapDataDownloads` | Downloads over 25 MB wait for Wi-Fi, unless the user allows mobile data. |
| Covered countries | `RoutingData.countries` in `Tileroam/Planning/RoutingData.swift` | Planning is refused with a clear message when the start or a selected item lies outside these countries. The bundled country outlines decide this. |
| Router | `Tileroam/Planning/ValhallaRouter.swift` | Stop order: `TripSolver` (nearest neighbour, 2-opt, relocation) on straight-line distances. Valhalla's cycling-time matrix gives nearly the same order but took 22 s for 30 stops on a Mac. The route: one `route` call with all stops as `break` locations. |
| Planner | `Tileroam/Planning/RoutePlanner.swift` | Picks a point inside each target, orders the stops, routes, and retries when a stop snaps outside its target. |
| Storage | Settings → Storage (`StorageView`) | Lists the downloaded tiles per 1° area, plus the main roads, with their size; swipe to remove. |

**Version coupling:** tiles are only guaranteed to load in the Valhalla version that built them. When you update valhalla-mobile, check which Valhalla version it contains (its README badge), then:
1. set the same version as `VALHALLA_VERSION` in `Tools/build_routing_tiles.sh`;
2. update `Tools/valhalla_build_extract.py` from that Valhalla tag;
3. regenerate `Tileroam/Resources/valhalla.json` (see below);
4. rebuild and upload the tiles (a new version).

## One-time setup

On the Mac:
```bash
brew install python@3.12 osmium-tool rclone
```

`Tools/build_routing_tiles.sh` creates its own Python environment with `pyvalhalla` (Valhalla's official tools), in `AssetPacks/build/routing/venv`. The build works on Apple Silicon Macs.

In Cloudflare (once):
1. **R2 → Create bucket:** `tileroam-routing`.
2. **Public access:** the bucket's Settings → Custom Domains → connect a domain, for example `tiles.petervanmanen.nl` (the domain's DNS must be on Cloudflare). That URL goes into `RoutingData.server`. The `r2.dev` address works for testing but is rate-limited; don't ship it.
3. **R2 → Manage API tokens → Create API token:** *Object Read & Write*, only for that bucket. Keep its Access Key ID and Secret Access Key yourself; the upload script reads them from environment variables.

R2 charges nothing for downloads (egress) and has 10 GB of storage free; Tileroam's data is about 2.2 GB per version.

## Building the routing data

```bash
ROUTING_CONCURRENCY=4 Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany
```

The first argument names the build (keep `west`, see "Versions"); the others are Geofabrik extract names under `europe/`. The script:

1. **Downloads** the extracts to `AssetPacks/build/routing/osm/`. It downloads them again when they're older than a week. The Netherlands is about 1.4 GB, Belgium 0.7 GB, Luxembourg 50 MB, Germany 4.9 GB.
2. **Merges** them with `osmium merge`. Country extracts overlap at the borders; building them separately would duplicate the border roads.
3. **Builds Valhalla's tiles** with `valhalla_build_tiles`. Left out, because cycling routes don't need them:
   - time zone, admin and traffic data;
   - car-only roads, driveways and car shortcuts (about 10% smaller).

   Footpaths stay in, so routes can cross pedestrian zones with the bike pushed. `ROUTING_PEDESTRIAN=False` drops them too, about 25% smaller in total, but then routes can't use pedestrian-only paths.
4. **Writes one tile extract** with all tiles, `AssetPacks/build/routing/routing-west.tar` (`valhalla_build_extract`). It's for the simulator, the tests and later repacks; it isn't uploaded.
5. **Packs the tiles for R2** (`Tools/pack_routing_tiles.py`), on every core:
   - gzips each tile to `AssetPacks/build/routing/r2/west/v<version>/…`;
   - writes the index `Tileroam/Resources/routing-west.json` (commit it with the app);
   - leaves out tiles more than 70 km from the covered countries (`Tools/routing_area_filter.py`, with the country outlines the app bundles). Planning never needs them: plans start and stop in those countries and download at most 60 km around. Germany's extract, for example, reaches 60°N and 25°E through its ferry routes. The countries come from `RoutingData.countries` (or `ROUTING_COUNTRIES="NL BE LU DE"`).

   `ROUTING_REPACK=1 Tools/build_routing_tiles.sh west` redoes only this step from the tile extract, without downloading or building again (6 minutes instead of 1½ hours).

   Test builds named `<name>-test` keep their index in the build folder instead.

Everything under `AssetPacks/build/` is ignored by Git. What the `west` build took on an M-series Mac with 8 GB of memory (`ROUTING_CONCURRENCY=4`, to spare memory):
- **Time:** about 1½ hours: 20 minutes downloading Germany, an hour building the tiles, 6 minutes packing.
- **Disk:** about 40 GB at the peak: the extracts (7 GB), the merged extract (7 GB, deleted after the tile build), Valhalla's temporary files (about 20 GB, deleted at the end), the tiles (5 GB), the tile extract (5.7 GB) and the packed tiles (2.2 GB).
- An external disk must be formatted for Mac (APFS or Mac OS Extended): FAT32 (MS-DOS) can't hold files over 4 GB.

## Uploading

```bash
R2_ACCOUNT_ID=<account ID> R2_ACCESS_KEY_ID=<key ID> R2_SECRET_ACCESS_KEY=<secret> R2_PUBLIC_URL=https://tiles.petervanmanen.nl Tools/upload_routing_r2.sh west
```

`Tools/upload_routing_r2.sh` uploads the version of the bundled index (`r2/west/v<version>/`) to `tileroam-routing/west/v<version>/` with rclone, 16 files at a time, with `Content-Encoding: gzip` and a year of caching (a version's files never change). Files already there are skipped, so an interrupted upload continues where it stopped. Afterwards it counts the tiles on R2 against the index and, with `R2_PUBLIC_URL`, downloads one through the public URL. `R2_BUCKET` changes the bucket.

Refresh the data every few months, because OpenStreetMap changes: build again, upload, then release the app with the new index. That makes a new **version**; see below.

## Versions

Every build is one version of the data. Tiles of different builds don't connect, because Valhalla numbers its graph per build, so each version has **its own folder** on R2 (`west/v1`, `west/v2`, …) and on the device (`Routing/west-v1`).
- **The number:** `Tools/build_routing_tiles.sh` raises it by one per build, starting from the bundled index (`"version"` in `Resources/routing-west.json`). A repack keeps it; `ROUTING_VERSION=<n>` overrides it.
- **The order:** build, upload, then release the app with the new index. Upload first: the app downloads from its index's folder, which must be complete.
- **Old versions:** keep their folders on R2 while app versions that use them are around (each app version downloads only from its own index's version). Deleting an old folder later is a matter of removing `west/v<n>/` in the Cloudflare dashboard or with `rclone purge`.
- **On the device:** an app update with a new index uses a new folder; `RoutingData.removeOtherVersions` deletes the old one before downloading, so a device never mixes versions.
- **Keep the build name `west`.** A new name works too (a new folder), but nothing needs it, and the name is internal.

## Why R2

Until October 2026 the tiles came as Apple-hosted asset packs (Background Assets) per 1° area. That ran into:
- **Apple's limit of 100 asset packs per app** (the documentation says 200), which forced large 1° areas: a plan downloaded 100–300 MB, and another country wouldn't fit;
- **slow, flaky App Store Connect** uploads (Transporter) and archiving (timeouts, HTTP 500);
- **versions:** a new build had to be new versions of the same packs, which a device could mix.

On R2 there's no limit on the number of files, so the app downloads Valhalla's own tiles, 0.25° for local roads, and a plan needs a fraction. The price is a server: the download requests reach Cloudflare. The bucket keeps no access logs (R2 doesn't by default), and the privacy policy says what a request reveals (an IP address and which map area). The municipality and postcode boundaries stay asset packs: 4 small packs, which suit them.

The app removes the asset-pack routing data of earlier TestFlight versions from devices (`RoutingData.removeAssetPackData`), and `Tools/clean_asset_packs.sh` lists the old `routing-benelux-*` and `routing-west-*` packs as unused, to archive with `ARCHIVE="routing-"` once no TestFlight build uses them.

## Testing in the simulator

- **The app, like production:** launch the Debug build with `-RoutingServer file://<repo>/AssetPacks/build/routing/r2/`. The app then downloads the tiles from the build folder instead of R2, decompresses them and plans exactly as on a device.
- **The app, simplest:** `-RoutingTar <repo>/AssetPacks/build/routing/routing-west.tar` uses the one file with all tiles. The screenshot and preview scripts use this.
- **Without either,** the app downloads from `RoutingData.server`.
- **Engine tests:** `TileroamTests/ValhallaEngineTests.swift` runs Valhalla in the simulator on a small Luxembourg-only build: once from its tile extract, and once by downloading its tiles as in production. Make it with:
  ```bash
  ROUTING_COUNTRIES=LU Tools/build_routing_tiles.sh lu-test luxembourg
  ```
  `WestRoutingTests` routes Kerkrade → Aachen across the border on the `west` tile extract. Without these files, the tests are skipped, as on GitHub.
- **Downloading:** `RoutingDownloadTests` (in `StorageTests.swift`) checks tile selection, downloading and decompressing, damaged tiles and version folders, against a temporary folder.
- **The rest:** the decoding and stop-ordering tests (`PlanningTests`) don't need any tiles.

## Adding countries

Germany was added in October 2026. For the next country:

1. **Use build `west`.** Countries whose routes should cross each other's borders must be in one build. The new country makes a new version of `west`. A plan still only downloads the tiles around it, so a bigger build doesn't make downloads bigger.
2. **Disk and time:** see "Building the routing data" above. There's no limit on R2's side.
3. **Boundaries:** the country needs municipality boundaries in Tileroam first:
   - `Tools/build_regions.py` for its `AssetPacks/Regions/<CC>-*.fmr`, plus its entry in `regions.json`;
   - add it to `Country.all` in `Tileroam/Geo/Regions.swift` and to Sources & Licenses in `SettingsView`;
   - rebuild the country outlines (`Tools/build_country_outlines.py`), which decide where planning is allowed;
   - upload its boundary pack (`Tools/upload_asset_packs.sh <CC>`), unless it's already in App Store Connect. Mind Apple's limit of 100 asset packs; the boundaries use 4.
4. **The app:**
   - Add the country code to `RoutingData.countries` (the build reads it too, for the reach filter).
   - Texts naming the countries: `RoutingError.outsideRegion` (`Tileroam/Planning/Routing.swift`), the introduction (`IntroView`), and their translations in the string catalog. The starting point search region is `PlaceSearch.region` (`StartPoint.swift`).
   - The tests that list the countries (`GeoTests`, `CountryTests`).
   - Docs: the READMEs, `docs/MANUAL.md`, `SUPPORT.md`, the App Store texts and review notes, `DATA-LICENSES.md` and this document.
   - Once Tileroam is an Apple Maps routing app (not in 1.0), regenerate the Routing App Coverage File:
     ```bash
     <venv with shapely>/bin/python Tools/build_routing_coverage.py NL BE LU DE
     ```
5. **Build and test:**
   ```bash
   ROUTING_CONCURRENCY=4 Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany <new country>
   ```
   - Add a route across the new border to `WestRoutingTests`.
   - In the simulator: `-RoutingServer file://<repo>/AssetPacks/build/routing/r2/ -RegionsDir <repo>/AssetPacks/Regions -PlanDemo YES -PlanDemoStart "<lat>,<lon>"` plans the demo route from any start, for example `50.8687,6.0835` on the Dutch–German border in Kerkrade.
6. **Upload** (`Tools/upload_routing_r2.sh west`) **before** releasing the app version with the new index.

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
