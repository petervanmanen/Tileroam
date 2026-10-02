# On-device route planning

Tileroam plans cycling routes on the iPhone or iPad itself, with [Valhalla](https://github.com/valhalla/valhalla) and OpenStreetMap data. Nothing is sent to a server.

The routing data comes from [Geofabrik](https://download.geofabrik.de)'s OpenStreetMap extracts. It's built on a Mac into one Valhalla *tile extract* and delivered to the app as an Apple-hosted asset pack, the same mechanism as the municipality and postcode boundaries.

Route planning currently covers **the Netherlands, Belgium and Luxembourg**, in one pack: `routing-benelux`.

## How it fits together

| Part | Where | What it does |
|---|---|---|
| Valhalla engine | Swift package [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), pinned to **0.6.3** in the Xcode project | Valhalla **3.6.3** compiled for iOS. Tileroam uses its `route` action with the `bicycle` costing. |
| Engine settings | `Tileroam/Resources/valhalla.json` | Valhalla's configuration, made with `valhalla_build_config` of the same version. At runtime `RoutingData.writeConfig` fills in the tile extract's path. The bicycle limit is raised to 60 locations, for 50 stops. |
| Routing data | asset pack `routing-benelux`, file `routing-benelux.tar` | Downloaded on demand the first time someone plans a route, then opened in place (`AssetPackManager.url(for:)`). |
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
4. **Packs the tiles** into one indexed tile extract, `AssetPacks/build/routing/routing-benelux.tar`, with `valhalla_build_extract`.
5. **Packages the asset pack** `AssetPacks/build/routing-benelux.aar`, downloaded on demand.

Everything under `AssetPacks/build/` is ignored by Git. For Benelux, expect a few GB of temporary disk space and 10–20 minutes on an M-series Mac.

## Uploading

```bash
ASC_KEY_ID=<KeyID> ASC_ISSUER_ID=<IssuerID> Tools/upload_asset_packs.sh routing-benelux
```

This uses the App Store Connect API key in `~/.appstoreconnect/private_keys/` and Transporter. The pack then has to be available to the builds that use it: TestFlight right away, and the App Store together with the version under review. The GitHub *Asset packs* workflow only handles the boundary packs; routing data is built and uploaded from a Mac, because it needs the large downloads.

Refresh the data every few months, because OpenStreetMap changes: run the build again, then the upload. The app picks up the new version of the pack by itself.

## Testing in the simulator

- **The app:** launch the Debug build with `-RoutingTar <repo>/AssetPacks/build/routing/routing-benelux.tar`. Without it, the app tries to download the asset pack.
- **Engine tests:** `TileroamTests/ValhallaEngineTests.swift` runs Valhalla in the simulator on `AssetPacks/build/routing/routing-lu-test.tar`, a small Luxembourg-only build. Make it with:
  ```bash
  Tools/build_routing_tiles.sh lu-test luxembourg
  ```
  Without that file, the engine tests are skipped, as on GitHub.
- **The rest:** the decoding and stop-ordering tests (`PlanningTests`) don't need any tiles.

## Adding countries

Example: adding Germany.

1. **Choose the group.** Countries whose routes should cross each other's borders must be in **one** build. Germany borders the Netherlands, Belgium and Luxembourg, so it joins that build. The pack name changes accordingly, for example `routing-benelux-de`, or keep a neutral name like `routing-west`.
2. **Mind the size.** Germany alone is about 4 GB of OpenStreetMap data and gives a much bigger tile extract. For several large countries, consider separate packs per region.
   - Separate packs don't connect, so routes can't cross between them.
   - The app would then need one Valhalla tile extract per pack, or a tile *directory* instead of a tar. valhalla-mobile supports both, as long as tiles that touch come from the same build.
3. **Build:**
   ```bash
   Tools/build_routing_tiles.sh benelux-de netherlands belgium luxembourg germany
   ```
4. **Update the app:**
   - In `RoutingData.swift`: add the country codes to `RoutingData.countries`, and set `packID` and `fileName` to the new pack (`routing-benelux-de`, `routing-benelux-de.tar`).
   - Update the text of `RoutingError.outsideRegion` in `Tileroam/Planning/Routing.swift`, and its translations in the string catalog.
   - Update `docs/MANUAL.md`, `docs/appstore/review-notes.md` and this document.
5. **Test** in the simulator with `-RoutingTar …/routing-benelux-de.tar`: plan a route that crosses the new border.
6. **Upload** the new pack (`Tools/upload_asset_packs.sh routing-benelux-de`), then ship the app version that uses it. Keep the old pack in App Store Connect until no supported app version uses it any more.

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
